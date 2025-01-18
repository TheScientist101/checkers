package main

import (
	"encoding/json"
	"github.com/pjebs/jsonerror"
	"github.com/unrolled/render"
	"gorm.io/gorm"
	"net/http"
)

type UserService struct {
	db *gorm.DB
}

type User struct {
	gorm.Model
	FirstName string `json:"first_name"`
	LastName  string `json:"last_name"`
	ELO       int
}

func (service *UserService) HandleRegister(w http.ResponseWriter, r *http.Request) {
	if r.Method == "POST" {
		user := &User{}
		err := json.NewDecoder(r.Body).Decode(user)

		user.ELO = 1200

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

		err = render.New().JSON(w, http.StatusCreated, user)
		if err != nil {
			panic(err)
		}
	}
}
