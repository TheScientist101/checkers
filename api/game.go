package main

import (
	"encoding/json"
	"errors"
	"log"
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gorilla/websocket"
	"github.com/notnil/chess"
	"github.com/pjebs/jsonerror"
	"github.com/scizorman/go-ndjson"
	"github.com/unrolled/render"
	"gorm.io/gorm"
)

const (
	// Time allowed to write a message to the peer.
	writeWait = 10 * time.Second

	// Time allowed to read the next pong message from the peer.
	pongWait = 60 * time.Second

	// Send pings to peer with this period. Must be less than pongWait.
	pingPeriod = (pongWait * 9) / 10
)

type Game struct {
	ID          uint `gorm:"primarykey"`
	CreatedAt   time.Time
	UpdatedAt   time.Time
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`
	PlayerWhite string
	PlayerBlack string
	PGN         string
	board       *chess.Game
}

func (g Game) getColor(uuid string) chess.Color {
	if g.PlayerWhite == uuid {
		return chess.White
	} else if g.PlayerBlack == uuid {
		return chess.Black
	}

	return chess.NoColor
}

type dataStream struct {
	conn              *websocket.Conn
	broadcast         chan interface{}
	activeGame        *Game
	lastBoardPosition string
}

type socketMessage struct {
	Type    string                 `json:"type"`
	Payload map[string]interface{} `json:"payload"`
}

type broadcastMessage struct {
	Type    string      `json:"type"`
	Payload interface{} `json:"payload"`
}

func (gs *GameService) readPump(user *User) {
	ds := gs.streams[user.UUID.String()]
	defer func(conn *websocket.Conn) {
		conn.Close()
		delete(gs.streams, user.UUID.String())
	}(ds.conn)

	if err := ds.conn.SetReadDeadline(time.Now().Add(pongWait)); err != nil {
		log.Printf("Error setting read deadline: %v", err)
	}

	ds.conn.SetPongHandler(func(string) error { return ds.conn.SetReadDeadline(time.Now().Add(pongWait)) })

	for {
		message := &socketMessage{}
		err := ds.conn.ReadJSON(message)
		if err != nil {
			var syntaxError *json.SyntaxError
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Println(err)
			} else if errors.As(err, &syntaxError) {
				ds.broadcast <- jsonerror.New(1, "Invalid JSON request", syntaxError.Error())
				continue
			}

			break
		}

		switch message.Type {
		case "move":
			gs.Move(user, message.Payload)
		case "position":
			gs.RetrieveLastPositionFEN(user)
		}
	}
}

func (gs *GameService) writePump(user *User) {
	ds := gs.streams[user.UUID.String()]

	ticker := time.NewTicker(pingPeriod)
	defer ds.conn.Close()

	for {
		select {
		case message := <-ds.broadcast:
			if err := ds.conn.SetWriteDeadline(time.Now().Add(writeWait)); err != nil {
				log.Printf("Error setting write deadline: %v", err)
			}

			err := ds.conn.WriteJSON(message)
			if err != nil {
				return
			}

		case <-ticker.C:
			ds.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := ds.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

type GameService struct {
	db           *gorm.DB
	us           *UserService
	gameRequests chan string
	streams      map[string]*dataStream
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
		streams: make(map[string]*dataStream),
	}

	go service.Matchmaker()

	http.HandleFunc("/matchmaking", service.NewGame)
	http.HandleFunc("/events", service.EventManager)

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
	Successful bool `json:"success"`
}

func (gs *GameService) NewGame(w http.ResponseWriter, r *http.Request) {
	SetCors(&w)

	user, userErr := gs.us.AuthenticateRequest(r.URL.Query().Get("email"), r.Header.Get("Authorization"))

	if userErr != nil {
		RenderJSONResponse(w, http.StatusUnauthorized, userErr)
		return
	}

	gs.gameRequests <- user.UUID.String()

	RenderJSONResponse(w, http.StatusOK, NewGameResponse{Successful: true})
}

func (gs *GameService) Matchmaker() {
	gs.gameRequests = make(chan string, 100)
	defer close(gs.gameRequests)

	for {
		players := []string{<-gs.gameRequests, <-gs.gameRequests}
		game := &Game{
			PlayerWhite: players[0],
			PlayerBlack: players[1],
			PGN:         "",
		}

		switch {
		case players[0] == players[1]:
			gs.gameRequests <- players[0]
		case gs.streams[players[0]] == nil && gs.streams[players[1]] == nil:
		case gs.streams[players[0]] == nil || gs.streams[players[0]].activeGame != nil:
			gs.gameRequests <- players[1]
		case gs.streams[players[1]] == nil || gs.streams[players[1]].activeGame != nil:
			gs.gameRequests <- players[0]
		default:
			gs.db.Create(game)
			for _, player := range players {
				gs.streams[player].broadcast <- &broadcastMessage{"game_start", game}
				gs.streams[player].activeGame = game
			}
		}
	}
}

type AuthenticationRequest struct {
	Email       string `json:"email"`
	AccessToken string `json:"access_token"`
}

type EventStreamResponse struct {
	Successful bool              `json:"success"`
	Error      map[string]string `json:"error"`
}

type AuthenticationResponse struct {
	Successful bool `json:"success"`
}

func (gs *GameService) EventManager(w http.ResponseWriter, r *http.Request) {
	conn, err := gs.upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println(err)
		return
	}

	request := &AuthenticationRequest{}

	err = conn.ReadJSON(request)
	if err != nil {
		log.Println(err)
		return
	}

	user, userErr := gs.us.AuthenticateRequest(request.Email, request.AccessToken)
	if userErr != nil {
		err = conn.WriteJSON(userErr)
		if err != nil {
			log.Println(err)
		}

		return
	}

	gs.streams[user.UUID.String()] = &dataStream{conn, make(chan interface{}, 10), nil, chess.StartingPosition().String()}
	gs.streams[user.UUID.String()].broadcast <- &AuthenticationResponse{true}

	go gs.readPump(user)
	go gs.writePump(user)
}

type MoveRequest struct {
	Notation     string
	GameID       float64
	RequestDraw  bool
	Resign       bool
	notationType string
}

type GameOutcome struct {
	Result    string `json:"result"`
	IsDraw    bool   `json:"is_draw"`
	Winner    string `json:"winner,omitempty"`
	Loser     string `json:"loser,omitempty"`
	Method    string `json:"method,omitempty"`
	NewRating int    `json:"new_rating"`
}

type MoveResponse struct {
	Successful bool              `json:"success"`
	Error      map[string]string `json:"error,omitempty"`
}

type GameRetrievalResponse struct {
	Successful bool   `json:"success"`
	Type       string `json:"type"`
	FEN        string `json:"fen"`
}

func (gs *GameService) RetrieveLastPositionFEN(user *User) {
	ds := gs.streams[user.UUID.String()]

	ds.broadcast <- &GameRetrievalResponse{true, "game_board", ds.lastBoardPosition}
}

func (gs *GameService) Move(user *User, message map[string]interface{}) {
	ds := gs.streams[user.UUID.String()]

	moveRequest := &MoveRequest{}

	var notationOk, gameIDOk, drawOk, resignOk, notationTypeOK bool

	moveRequest.Notation, notationOk = message["notation"].(string)
	moveRequest.notationType, notationTypeOK = message["notation_type"].(string)
	if !notationTypeOK {
		moveRequest.notationType = "algebraic"
	}

	moveRequest.GameID, gameIDOk = message["game_id"].(float64)
	moveRequest.RequestDraw, drawOk = message["request_draw"].(bool)
	moveRequest.Resign, resignOk = message["resign"].(bool)

	if !notationOk {
		ds.broadcast <- &MoveResponse{
			false,
			jsonerror.New(62, "Move request improperly formatted.", "Failed to parse notation.").Render(),
		}
		return
	}

	if !gameIDOk {
		ds.broadcast <- &MoveResponse{
			false,
			jsonerror.New(62, "Move request improperly formatted.", "Failed to parse game_id.").Render(),
		}
	}

	if !drawOk {
		ds.broadcast <- &MoveResponse{
			false,
			jsonerror.New(62, "Move request improperly formatted.", "Failed to parse request_draw.").Render(),
		}
	}

	if !resignOk {
		ds.broadcast <- &MoveResponse{
			false,
			jsonerror.New(62, "Move request improperly formatted.", "Failed to parse resign.").Render(),
		}
	}

	game := &Game{}
	if gs.db.First(game, "id == ?", moveRequest.GameID).RowsAffected == 0 {
		log.Println("Game does not exist with given ID: ", moveRequest.GameID)
		ds.broadcast <- &MoveResponse{
			false,
			jsonerror.New(61, "Game does not exist with given ID.", "Game does not exist with given ID: "+strconv.FormatFloat(moveRequest.GameID, 'f', -1, 64)).Render(),
		}
		return
	}

	if game.board == nil && len(game.PGN) != 0 {
		pgn, err := chess.PGN(strings.NewReader(game.PGN))
		if err != nil {
			ds.broadcast <- &MoveResponse{
				false,
				jsonerror.New(28, "Internal server error", "Error parsing game data").Render(),
			}
		}

		game.board = chess.NewGame(pgn, chess.UseNotation(chess.AlgebraicNotation{}))
	} else if len(game.PGN) == 0 {
		game.board = chess.NewGame(chess.UseNotation(chess.AlgebraicNotation{}))
	}

	var color chess.Color

	if color = game.getColor(user.UUID.String()); color == chess.NoColor {
		ds.broadcast <- &MoveResponse{false, jsonerror.New(60, "Game does not belong to you", "Game does not belong to you").Render()}
		return
	}

	if game.board.Position().Turn() != color {
		ds.broadcast <- &MoveResponse{false, jsonerror.New(59, "It is not your turn", "It is not your turn").Render()}
		return
	}

	var decoder chess.Notation

	switch moveRequest.notationType {
	case "uci":
		decoder = chess.UCINotation{}
	case "long algebraic":
		decoder = chess.LongAlgebraicNotation{}
	default:
		decoder = chess.AlgebraicNotation{}
	}

	move, err := decoder.Decode(game.board.Position(), moveRequest.Notation)

	if err != nil {
		ds.broadcast <- &MoveResponse{
			false,
			jsonerror.New(58, "Illegal move", err.Error()).Render(),
		}
		return
	}

	// For later sending to other clients
	moveRequest.Notation = chess.AlgebraicNotation{}.Encode(game.board.Position(), move)

	err = game.board.Move(move)
	if err != nil {
		ds.broadcast <- &MoveResponse{false, jsonerror.New(58, "Illegal move", err.Error()).Render()}
		return
	}

	game.PGN = game.board.String()

	gs.db.Save(game)

	ds.broadcast <- &MoveResponse{true, nil}
	for _, player := range []string{game.PlayerWhite, game.PlayerBlack} {
		gs.streams[player].broadcast <- &broadcastMessage{Type: "move", Payload: moveRequest}
		gs.streams[player].activeGame = game
		gs.streams[player].lastBoardPosition = game.board.FEN()
	}

	if game.board.Outcome() == chess.NoOutcome {
		return
	}

	var opponentUUID string

	if color == chess.White {
		opponentUUID = game.PlayerBlack
	} else {
		opponentUUID = game.PlayerWhite
	}

	opponentStream := gs.streams[opponentUUID]

	opponent, err := gs.us.GetUser(opponentUUID)
	if err != nil {
		panic(err)
	}

	gameResult := &GameOutcome{
		Result: game.board.Outcome().String(),
		Method: game.board.Method().String(),
		IsDraw: false,
	}

	switch game.board.Outcome() {
	case chess.WhiteWon:
		if color == chess.White {
			gameResult.Winner = user.UUID.String()
			gameResult.Loser = opponentUUID
			gs.UpdateELO(user, opponent, 1.0)
		} else {
			gameResult.Winner = opponentUUID
			gameResult.Loser = user.UUID.String()
			gs.UpdateELO(opponent, user, 1.0)
		}
	case chess.BlackWon:
		if color == chess.Black {
			gameResult.Winner = user.UUID.String()
			gameResult.Loser = opponentUUID
			gs.UpdateELO(user, opponent, 1.0)
		} else {
			gameResult.Winner = opponentUUID
			gameResult.Loser = user.UUID.String()
			gs.UpdateELO(opponent, user, 1.0)
		}
	case chess.Draw:
		gameResult.IsDraw = true
		gs.UpdateELO(user, opponent, 0.5)
	}

	ds.broadcast <- &broadcastMessage{Type: "game_result", Payload: gameResult}
	opponentStream.broadcast <- &broadcastMessage{Type: "game_result", Payload: gameResult}

	ds.activeGame = nil
	opponentStream.activeGame = nil
}

// CalculateProbability Calculates probability for u1 to win the game
func (gs *GameService) CalculateProbability(u1, u2 *User) float64 {
	return 1.0 / (1 + math.Pow(10, float64(u2.ELO-u1.ELO)/400.0))
}

func (gs *GameService) CalculateELOK(user *User) float64 {
	return max(400.0/float64(1+gs.db.Where("player_white = ?", user.UUID.String()).Or("player_black = ?", user.UUID.String()).Where(
		"created_at >= ?",
		time.Now().Add(-time.Hour*24*90),
	).Find(&Game{}).RowsAffected), 30)
}

func (gs *GameService) UpdateELO(winner *User, loser *User, outcome float64) {
	// Probabilities to win for the winner and loser
	winnerProbability := gs.CalculateProbability(winner, loser)
	loserProbability := gs.CalculateProbability(loser, winner)

	kWinner := gs.CalculateELOK(winner)
	kLoser := gs.CalculateELOK(loser)

	winner.ELO += int(kWinner * (outcome - winnerProbability))
	loser.ELO += int(kLoser * ((1 - outcome) - loserProbability))

	gs.db.Save(winner)
	gs.db.Save(loser)
}
