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
	FirstName string
	LastName  string
	GUID      string
	Password  []byte
	ELO       int
	Email     string
}

type UnverifiedUser struct {
	gorm.Model
	FirstName string
	LastName  string
	GUID      string
	Email     string
	Token     string
	Password  []byte
	Expiry    time.Time
}

type NewUserRequest struct {
	FirstName string `json:"first_name"`
	LastName  string `json:"last_name"`
	Email     string `json:"email" gorm:"unique"`
	Password  string `json:"password"`
}

type NewUserResponse struct {
	Successful bool              `json:"success"`
	Error      map[string]string `json:"error"`
}

func ShowError(w http.ResponseWriter) {
	t, err := template.New("error.html").ParseFiles("templates/error.html")
	if err != nil {
		log.Fatal(err)
	}

	err = t.Execute(w, nil)
	if err != nil {
		log.Fatal(err)
	}
}

func (service *UserService) VerifyUser(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" {
		return
	}

	unverifiedUser := &UnverifiedUser{
		Token: r.URL.Query().Get("token"),
		Email: r.URL.Query().Get("email"),
	}

	service.db.First(&unverifiedUser, "email = ? AND token = ?", unverifiedUser.Email, unverifiedUser.Token)

	if time.Now().After(unverifiedUser.Expiry) {
		t, err := template.New("verification-failed.html").ParseFiles("templates/verification-failed.html")
		if err != nil {
			log.Fatal(err)
		}

		err = t.Execute(w, unverifiedUser.FirstName)
		if err != nil {
			log.Fatal(err)
		}
	}

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

	if err := service.db.Delete(unverifiedUser).Error; err != nil {
		log.Println(err)
		ShowError(w)
		return
	}

	t, err := template.New("successfully-verified.html").ParseFiles("./templates/successfully-verified.html")
	if err != nil {
		log.Fatalln(err)
	}

	err = t.Execute(w, user.FirstName)
	if err != nil {
		panic(err)
	}
}

func (service *UserService) SendVerificationEmail(user UnverifiedUser, host string) {
	t, err := template.New("verify-email.html").ParseFiles("./templates/verify-email.html")

	if err != nil {
		log.Fatalln(err)
	}

	var tpl bytes.Buffer
	err = t.Execute(&tpl, fmt.Sprintf("http://%s/verify?token=%s&email=%s", host, user.Token, url.QueryEscape(user.Email)))

	if err != nil {
		panic(err)
	}

	result := tpl.String()

	m := gomail.NewMessage()
	m.SetHeader("From", service.emailDialer.Username)
	m.SetHeader("To", user.Email)
	m.SetHeader("Subject", "Verify Email")
	m.SetBody("text/html", result)

	err = service.emailDialer.DialAndSend(m)
	if err != nil {
		log.Fatalln(err)
	}
}

func NewUserError(code int, error string, message string) *NewUserResponse {
	return &NewUserResponse{
		Successful: false,
		Error:      jsonerror.New(code, error, message).Render(),
	}
}

func (service *UserService) HandleRegister(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		return
	}

	request := &NewUserRequest{}

	if err := json.NewDecoder(r.Body).Decode(request); err != nil {
		panic(err)
	}

	user, err := service.ProcessUser(request, w, r.Host)
	if err != nil {
		log.Println(err)
		return
	}

	dbErr := service.db.Create(user).Error
	if dbErr != nil {
		response := NewUserError(31, "Error adding user to database", dbErr.Error())

		err := render.New().JSON(
			w,
			http.StatusInternalServerError,
			response,
		)

		if err != nil {
			panic(err)
		}

		return
	}

	if err := render.New().JSON(w, http.StatusCreated, &NewUserResponse{Successful: true}); err != nil {
		panic(err)
	}
}

func (service *UserService) ProcessUser(request *NewUserRequest, w http.ResponseWriter, host string) (*UnverifiedUser, error) {
	user := &UnverifiedUser{
		FirstName: request.FirstName,
		LastName:  request.LastName,
		GUID:      guid.NewString(),
	}

	if _, err := mail.ParseAddress(request.Email); err != nil {
		response := NewUserError(32, "Invalid email", err.Error())
		err := render.New().JSON(w, http.StatusBadRequest, response)

		return nil, err
	}

	if service.db.First(&User{}, "email = ?", request.Email).Error.Error() != "record not found" {
		response := NewUserError(
			33,
			"Account already exists with email",
			"Account already exists with email: "+request.Email,
		)

		err := render.New().JSON(
			w,
			http.StatusCreated,
			response,
		)

		return nil, err
	}
	user.Email = request.Email

	user.Password = argon2.IDKey([]byte(request.Password), []byte(user.GUID), 1, 64*1024, 4, 32)

	token := make([]byte, 32)
	_, err := rand.Read(token)
	if err != nil {
		return nil, err
	}

	user.Token = hex.EncodeToString(token)
	user.Expiry = time.Now().Add(time.Hour * 24 * 7)

	go service.SendVerificationEmail(*user, host)

	return user, nil
}
