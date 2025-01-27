package main

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"time"

	"github.com/gorilla/websocket"
	"github.com/pjebs/jsonerror"
	"github.com/scizorman/go-ndjson"
	"github.com/unrolled/render"
	"gorm.io/gorm"
)

type Game struct {
	gorm.Model
	Players [2]string `gorm:"type:text[]"`
	Moves   []string  `gorm:"type:text[]"`
}

type GameService struct {
	db           *gorm.DB
	us           *UserService
	gameRequests chan string
	notifiers    map[string]chan *Game
	upgrader     websocket.Upgrader
}

func NewGameService(db *gorm.DB, us *UserService) *GameService {
	service := &GameService{
		db: db,
		us: us,
		upgrader: websocket.Upgrader{
			ReadBufferSize:  1024,
			WriteBufferSize: 1024,
			CheckOrigin: func(r *http.Request) bool {
				return true
			},
		},
		notifiers: make(map[string]chan *Game),
	}

	go service.Matchmaker()
	return service
}

func JSONError(w http.ResponseWriter, status, code int, error string, message string) {
	err := render.New().JSON(w, status, jsonerror.New(code, error, message).Render())
	if err != nil {
		log.Println(err)
	}
}

// RenderNDJSONResponse Utility function to render NDJSON reponses
func RenderNDJSONResponse(w http.ResponseWriter, status int, response interface{}) {
	w.Header().Set("Content-Type", "application/x-ndjson")
	marshalled, err := ndjson.Marshal(response)
	if err != nil {
		log.Println(err)
		return
	}

	w.Header().Set("Content-Length", strconv.Itoa(len(marshalled)))
	w.WriteHeader(status)
	_, err = w.Write(marshalled)
	if err != nil {
		log.Println(err)
	}
}

type NewGameResponse struct {
	Successful bool `json:"successful"`
}

func (gs *GameService) NewGame(w http.ResponseWriter, r *http.Request) {
	user, userErr := gs.us.AuthenticateRequest(r.URL.Query().Get("email"), r.Header.Get("Authorization"))
	if userErr != nil {
		RenderJSONResponse(w, http.StatusUnauthorized, userErr)
	}

	gs.gameRequests <- user.UUID.String()

	RenderJSONResponse(w, http.StatusOK, NewGameResponse{Successful: true})
}

func (gs *GameService) Matchmaker() {
	gs.gameRequests = make(chan string)
	defer close(gs.gameRequests)

	for {
		players := [2]string{<-gs.gameRequests, <-gs.gameRequests}
		game := &Game{
			Players: players,
			Moves:   make([]string, 0),
		}

		switch {
		case gs.notifiers[players[0]] == nil && gs.notifiers[players[1]] == nil:
			return
		case gs.notifiers[players[0]] == nil || len(gs.notifiers[players[0]]) == 0:
			gs.gameRequests <- players[1]
		case gs.notifiers[players[1]] == nil || len(gs.notifiers[players[1]]) == 0:
			gs.gameRequests <- players[0]
		default:
			gs.notifiers[players[0]] <- game
			gs.notifiers[players[1]] <- game
			gs.db.Save(game)
		}
	}
}

func (gs *GameService) EventManager(w http.ResponseWriter, r *http.Request) {
	conn, err := gs.upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Print("upgrade:", err)
	}
	defer func(c *websocket.Conn) {
		err := c.Close()
		if err != nil {
			log.Print("close:", err)
		}
	}(conn)

	conn.ReadJSON()

	user, userErr := gs.us.AuthenticateRequest(r.URL.Query().Get("email"), r.Header.Get("Authorization"))
	if userErr != nil {
		RenderJSONResponse(w, http.StatusUnauthorized, userErr)
	}

	gs.notifiers[user.UUID.String()] = make(chan *Game, 1)
	defer close(gs.notifiers[user.UUID.String()])

	w.Header().Set("Transfer-Encoding", "chunked")

	for {
		select {
		case game := <-gs.notifiers[user.UUID.String()]:
			RenderNDJSONResponse(w, http.StatusOK, game)
			gs.PlayGame(w, r, user, game)
		case <-time.After(time.Second):
			_, err := w.Write([]byte("\n"))
			if err != nil {
				log.Println(err)
				return
			}
		}
	}
}

type MoveRequest struct {
	notation string
}

type MoveResponse struct {
	Successful bool         `json:"successful"`
	Error      jsonerror.JE `json:"error,omitempty"`
}

func (gs *GameService) PlayGame(w http.ResponseWriter, r *http.Request, user *User, game *Game) {
	var request MoveRequest
	for {
		err := json.NewDecoder().Decode(&request)
		if err != nil {
			log.Println(err)
			RenderNDJSONResponse(w, http.StatusBadRequest, &MoveResponse{false, jsonerror.New(
				1,
				"Invalid JSON Request",
				err.Error(),
			)})
		}
	}
}
