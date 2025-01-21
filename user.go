package main

import (
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"html/template"
	"log"
	"net/http"
	"net/mail"
	"net/url"
	"strings"
	"time"

	"github.com/beevik/guid"
	"github.com/pjebs/jsonerror"
	"github.com/unrolled/render"
	"golang.org/x/crypto/argon2"
	"gopkg.in/gomail.v2"
	"gorm.io/gorm"
)

type UserService struct {
	db          *gorm.DB
	emailDialer *gomail.Dialer
}

type User struct {
	gorm.Model
	FirstName string `gorm:"not null"`
	LastName  string `gorm:"not null"`
	GUID      string `gorm:"unique,not null"`
	Password  []byte `gorm:"not null"`
	ELO       int    `gorm:"not null"`
	Email     string `gorm:"unique,not null"`
}

type UnverifiedUser struct {
	gorm.Model
	FirstName string    `gorm:"not null"`
	LastName  string    `gorm:"not null"`
	GUID      string    `gorm:"not null"`
	Email     string    `gorm:"not null"`
	Token     string    `gorm:"not null"`
	Password  []byte    `gorm:"not null"`
	Expiry    time.Time `gorm:"not null"`
}

type NewUserRequest struct {
	FirstName string `json:"first_name"`
	LastName  string `json:"last_name"`
	Email     string `json:"email"`
	Password  string `json:"password"`
}

type NewUserResponse struct {
	Successful bool              `json:"success"`
	Error      map[string]string `json:"error,omitempty"`
}

// Utility function to render error templates
func RenderErrorTemplate(w http.ResponseWriter, templateName string, data interface{}) {
	if err := render.New().HTML(w, http.StatusOK, templateName, data); err != nil {
		log.Fatal(err)
	}
}

// Utility function to render JSON responses
func RenderJSONResponse(w http.ResponseWriter, status int, response interface{}) {
	if err := render.New().JSON(w, status, response); err != nil {
		log.Println(err)
	}
}

// Utility function to generate random tokens
func GenerateRandomToken() (string, error) {
	token := make([]byte, 32)
	if _, err := rand.Read(token); err != nil {
		return "", err
	}
	return hex.EncodeToString(token), nil
}

// Utility function to hash passwords using argon2
func HashPassword(password string, salt string) []byte {
	return argon2.IDKey([]byte(password), []byte(salt), 1, 64*1024, 4, 32)
}

// NewUserError is a helper function to create a NewUserResponse with an error
func NewUserError(code int, error, message string) *NewUserResponse {
	return &NewUserResponse{
		Successful: false,
		Error:      jsonerror.New(code, error, message).Render(),
	}
}

// Check if a user with the given email exists in the database
func (service *UserService) EmailExists(email string) bool {
	return service.db.First(&User{}, "email = ?", email).RowsAffected > 0
}

// Check if an unverified user with the given email and token exists in the database
func (service *UserService) UnverifiedUserExists(email, token string) bool {
	var unverifiedUser UnverifiedUser
	return service.db.First(&unverifiedUser, "email = ? AND token = ?", email, token).Error == nil
}

// Create and send a verification email
func (service *UserService) SendVerificationEmail(user UnverifiedUser, host string) {
	tpl, err := ParseTemplate("verify-email.tmpl", fmt.Sprintf("http://%s/verify?token=%s&email=%s", host, user.Token, url.QueryEscape(user.Email)))
	if err != nil {
		log.Fatalln(err)
	}

	m := gomail.NewMessage()
	m.SetHeader("From", service.emailDialer.Username)
	m.SetHeader("To", user.Email)
	m.SetHeader("Subject", "Verify Email")
	m.SetBody("text/html", tpl)

	if err := service.emailDialer.DialAndSend(m); err != nil {
		log.Fatalln(err)
	}
}

// Parse and execute a template file
func ParseTemplate(templateName, data string) (string, error) {
	t, err := template.New(templateName).ParseFiles("./templates/" + templateName)
	if err != nil {
		return "", err
	}

	var tpl bytes.Buffer
	if err := t.Execute(&tpl, data); err != nil {
		return "", err
	}

	return tpl.String(), nil
}

func ShowError(w http.ResponseWriter) {
	RenderErrorTemplate(w, "error", nil)
}

func (service *UserService) VerifyUser(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" {
		return
	}

	email := strings.ToLower(r.URL.Query().Get("email"))
	token := r.URL.Query().Get("token")

	if !service.UnverifiedUserExists(email, token) {
		RenderErrorTemplate(w, "verification-failed", map[string]string{"Error": "we couldn't find your verification link in our database."})
		return
	}

	var unverifiedUser UnverifiedUser
	service.db.First(&unverifiedUser, "email = ? AND token = ?", email, token)

	// Check if verification token has expired
	if time.Now().After(unverifiedUser.Expiry) {
		RenderErrorTemplate(w, "verification-failed", map[string]string{
			"Name":  unverifiedUser.FirstName,
			"Error": "too much time has passed since the verification email was sent.",
		})
		return
	}

	// Check if the user already exists
	if service.EmailExists(email) {
		RenderErrorTemplate(w, "verification-failed", map[string]string{
			"Name":  unverifiedUser.FirstName,
			"Error": "an account with this email already exists.",
		})
		return
	}

	// Create the new user
	user := &User{
		FirstName: unverifiedUser.FirstName,
		LastName:  unverifiedUser.LastName,
		GUID:      unverifiedUser.GUID,
		Password:  unverifiedUser.Password,
		ELO:       1200,
		Email:     unverifiedUser.Email,
	}

	if err := service.db.Create(user).Error; err != nil {
		log.Println(err)
		ShowError(w)
		return
	}

	// Delete the unverified user
	if err := service.db.Delete(&unverifiedUser).Error; err != nil {
		log.Println(err)
		ShowError(w)
		return
	}

	// Send the success response
	if tpl, err := ParseTemplate("successfully-verified.tmpl", user.FirstName); err != nil {
		panic(err)
	} else {
		w.Write([]byte(tpl))
	}
}

func (service *UserService) HandleRegister(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		return
	}

	var request NewUserRequest
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		log.Println(err)
		ShowError(w)
		return
	}

	user, err := service.ProcessUser(&request, w, r.Host)
	if err != nil {
		log.Println(err)
		return
	}

	// Create the unverified user
	if err := service.db.Create(user).Error; err != nil {
		response := NewUserError(31, "Error adding user to database", err.Error())
		RenderJSONResponse(w, http.StatusInternalServerError, response)
		return
	}

	RenderJSONResponse(w, http.StatusCreated, &NewUserResponse{Successful: true})
}

func (service *UserService) ProcessUser(request *NewUserRequest, w http.ResponseWriter, host string) (*UnverifiedUser, error) {
	email := strings.ToLower(request.Email)
	if _, err := mail.ParseAddress(email); err != nil {
		response := NewUserError(32, "Invalid email", err.Error())
		RenderJSONResponse(w, http.StatusBadRequest, response)
		return nil, fmt.Errorf("invalid email: %s", email)
	}

	// Check if email already exists
	if service.EmailExists(email) {
		response := NewUserError(33, "Account already exists with email", "Account already exists with email: "+email)
		RenderJSONResponse(w, http.StatusConflict, response)
		return nil, fmt.Errorf("account already exists with email: %s", email)
	}

	// Generate the unverified user
	user := &UnverifiedUser{
		FirstName: request.FirstName,
		LastName:  request.LastName,
		GUID:      guid.NewString(),
		Email:     email,
		Password:  HashPassword(request.Password, guid.NewString()),
	}

	// Generate token and expiry
	token, err := GenerateRandomToken()
	if err != nil {
		return nil, err
	}

	user.Token = token
	user.Expiry = time.Now().Add(time.Hour * 24 * 7)

	// Send verification email asynchronously
	go service.SendVerificationEmail(*user, host)

	return user, nil
}
