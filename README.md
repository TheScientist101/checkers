# Checkers, the Chess API

Checkers is a simple and flexible chess API built with Go, perfect for building multiplayer chess apps. It makes things like special moves, user accounts, email verification, and real-time game updates through WebSockets easy to set up, so you can focus on the fun part of creating your game.

## Key Features

- **Support for Special Chess Moves**  
  Thanks to https://github.com/notnil/chess, Checkers supports all special chess moves, including:
    - Castling
    - En passant
    - Pawn promotion

- **User Management**
    - Create, update, and delete user accounts
    - Email address verification to deter bots

- **Game Streaming via WebSockets**  
  Real-time game streaming using WebSockets, allowing users to play live games and receive updates instantly.

- **Computer-Friendly Notation Support**  
  When sending moves to the server, Checkers supports various notation formats including:
  - Algebraic
  - Long Algebraic
  - UCI
  
  It also allows you to request a FEN of the board at any time for easier parsing (as used in the demo client made by @Anakkaris).

## Self Hosting

To host your own instance of Checkers, follow the steps below to install and run the API locally.

### Prerequisites

- Go 1.18+ installed

### Steps

1. **Clone the Repository:**

   ```bash
   git clone https://github.com/TheScientist101/checkers.git
   cd checkers
   ```

2. **Install Dependencies:**

   Use Go modules to install the required dependencies.

   ```bash
   go mod tidy
   ```

3. **Configure the Database:**

    By default, Checkers creates a sqlite database called `development.db` be sure to change the line below if you would like to use a different database.

   ```go
   db, err := gorm.Open(sqlite.Open("development.db")
   ```

4. **Run the API:**

   Once your environment is ready, start the server.

   ```bash
   go run main.go
   ```

5. **Access the API:**

   By default, the API will run on `http://localhost:8080`. You can now start using the endpoints to create users, and play games.

## Endpoints

### User Management

- `POST /register`  
  Registers a new user with a first name, last name, email and password.

- `POST /login`  
  Authenticates a user and returns a JWT token.

### Game Management

- `GET /matchmaking`
  Puts in a request for a new game, ensure that you have established a websocket connection to the `/events` endpoint to be notified when your game starts.

### WebSockets

WebSocket connections are used for real-time game updates. After establishing a connection at the `/events` endpoint, clients will receive live notifications whenever a move is made, or the game state changes.

Actual documentation coming soon...

## Contributing

We welcome contributions! If you would like to contribute to Checkers, please fork the repository and create a pull request with your changes.
