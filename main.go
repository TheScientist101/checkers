package main

import (
	"gopkg.in/gomail.v2"
	"log"
	"net/http"
	"os"

	"github.com/joho/godotenv"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func main() {
	err := godotenv.Load()
	if err != nil {
		log.Fatal("Error loading .env file")
	}

	db, err := gorm.Open(sqlite.Open("development.db"), &gorm.Config{})
	if err != nil {
		panic(err)
	}

	if err = db.AutoMigrate(&User{}); err != nil {
		panic(err)
	}

	if err = db.AutoMigrate(&UnverifiedUser{}); err != nil {
		panic(err)
	}

	userService := &UserService{
		db:          db,
		emailDialer: gomail.NewDialer("smtp.gmail.com", 587, os.Getenv("EMAIL_ADDRESS"), os.Getenv("EMAIL_PASSWORD")),
	}

	http.HandleFunc("/register", userService.HandleRegister)
	http.HandleFunc("/verify", userService.VerifyUser)

	err = http.ListenAndServe(":8080", nil)
}
