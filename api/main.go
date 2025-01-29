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

	if err = db.AutoMigrate(&Game{}); err != nil {
		panic(err)
	}

	userService := NewUserService(
		db,
		gomail.NewDialer("smtp.gmail.com", 587, os.Getenv("EMAIL_ADDRESS"), os.Getenv("EMAIL_PASSWORD")),
		os.Getenv("PRIVATE_KEY_PATH"),
		os.Getenv("PUBLIC_KEY_PATH"),
	)

	NewGameService(db, userService)

	err = http.ListenAndServe(":8080", nil)
	if err != nil {
		panic(err)
	}
}
