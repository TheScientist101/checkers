package main

import (
	"encoding/json"
	"github.com/beevik/guid"
	"github.com/pjebs/jsonerror"
	"github.com/unrolled/render"
	"golang.org/x/crypto/argon2"
	"gorm.io/gorm"
	"net/http"
)

type UserService struct {
	db *gorm.DB
}

type User struct {
	gorm.Model
	FirstName string
	LastName  string
	GUID      string
	Password  []byte
	ELO       int
}

type NewUserRequest struct {
	FirstName string `json:"first_name"`
	LastName  string `json:"last_name"`
	Password  string `json:"password"`
}

type NewUserResponse struct {
	Successful bool `json:"success"`
}

func (service *UserService) HandleRegister(w http.ResponseWriter, r *http.Request) {
	if r.Method == "POST" {
		request := &NewUserRequest{}
		err := json.NewDecoder(r.Body).Decode(request)

		user := &User{
			FirstName: request.FirstName,
			LastName:  request.LastName,
			ELO:       1200,
			GUID:      guid.NewString(),
		}
		user.Password = argon2.IDKey([]byte(request.Password), []byte(user.GUID), 1, 64*1024, 4, 32)

		if err != nil {
			panic(err)
		}

		dbErr := service.db.Create(user).Error
		if dbErr != nil {
			err := render.New().JSON(
				w,
				http.StatusInternalServerError,
				jsonerror.New(31, "Error adding user to database", dbErr.Error()).Render(),
			)

			if err != nil {
				panic(err)
			}

			return
		}

		err = render.New().JSON(w, http.StatusCreated, &NewUserResponse{Successful: true})
		if err != nil {
			panic(err)
		}
	}
}
