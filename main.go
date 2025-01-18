package main

import (
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
	"net/http"
)

func main() {
	db, err := gorm.Open(sqlite.Open("development.db"), &gorm.Config{})
	if err != nil {
		panic(err)
	}

	err = db.AutoMigrate(&User{})
	if err != nil {
		panic(err)
	}

	userService := &UserService{db: db}

	http.HandleFunc("/register", userService.HandleRegister)

	err = http.ListenAndServe(":8080", nil)
}
