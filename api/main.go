package main

import (
	"log"
	"net/http"
	"os"

	"gopkg.in/gomail.v2"

	_ "github.com/joho/godotenv/autoload"
	"gorm.io/driver/postgres"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func main() {
	var db *gorm.DB
	var err error

	if os.Getenv("POSTGRES_DSN") != "" {
		log.Println("Using POSTGRES_DSN from environment")
		dsn := os.Getenv("POSTGRES_DSN")
		db, err = gorm.Open(postgres.Open(dsn), &gorm.Config{})
	} else {
		db, err = gorm.Open(sqlite.Open("development.db"), &gorm.Config{})
	}
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
