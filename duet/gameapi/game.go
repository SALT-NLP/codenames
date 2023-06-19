package gameapi

import (
	"encoding/json"
	"math/rand"
	"strconv"
	"sync"
	"time"
)

type Color int

const (
	Tan Color = iota
	Green
	Black
)

func (c Color) String() string {
	switch c {
	case Green:
		return "g"
	case Black:
		return "b"
	default:
		return "t"
	}
}

func (c Color) MarshalJSON() ([]byte, error) {
	return json.Marshal(c.String())
}

// Seed wraps an int64 with a custom JSON marshaller to marshal
// it as a string. We use the full 64-bit range, but Javascript
// Numbers aren't capable of representing the full range of 64-bit
// integers, so we always represent it as a string on the client.
type Seed int64

func (s *Seed) UnmarshalJSON(b []byte) error {
	var str string
	if err := json.Unmarshal(b, &str); err != nil {
		return err
	}
	i, err := strconv.ParseInt(str, 10, 64)
	*s = Seed(i)
	return err
}

func (s Seed) MarshalJSON() ([]byte, error) {
	return json.Marshal(strconv.FormatInt(int64(s), 10))
}

// GameState encapsulates enough data to reconstruct
// a Game's state. It's used to recreate games after
// a process restart.
type GameState struct {
	mu      sync.Mutex        `json:"-"`
	changed chan struct{}     `json:"-"`
	players map[string]Player `json:"-"`
	Seed    Seed              `json:"seed"`
	Events  []Event           `json:"events"`
	WordSet []string          `json:"word_set"`
}

type Event struct {
	Number            int      `json:"number"`
	Type              string   `json:"type"`
	PlayerID          string   `json:"player_id"`
	Name              string   `json:"name"`
	Team              int      `json:"team"`
	Index             int      `json:"index"`
	Message           []string `json:"message"`
	Num_target_words  int      `json:"num_target_words"`
	UserAge           string   `json:"user_age"`
	UserGender        string   `json:"user_gender"`
	UserCountry       string   `json:"user_country"`
	UserNativeSpeaker bool     `json:"user_native_speaker"`
	ErrorMessage      string   `json:"error_message"`
	OneSeenWords      []string `json:"one_seen_words"`
	TwoSeenWords      []string `json:"two_seen_words"`
	Time              int64    `json:"timestamp"`
	Rationale         string   `json:"rationale"`
}

type Player struct {
	Team     int       `json:"team"`
	Name     string    `json:"name"`
	LastSeen time.Time `json:"last_seen"`
}

func NewState(seed int64, words []string) GameState {
	return GameState{
		changed: make(chan struct{}),
		players: make(map[string]Player),
		Seed:    Seed(seed),
		Events:  []Event{},
		WordSet: words,
	}
}

type Game struct {
	GameState    `json:"state"`
	CreatedAt    time.Time       `json:"created_at"`
	Words        []string        `json:"words"`
	OneLayout    []Color         `json:"one_layout"`
	TwoLayout    []Color         `json:"two_layout"`
	GameID       string          `json:"game_id"`
	OneSeenWords map[string]bool `json:"one_seen_words"`
	TwoSeenWords map[string]bool `json:"two_seen_words"`
}

func (gs *GameState) notifyAll() {
	close(gs.changed)
	gs.changed = make(chan struct{})
}

func (gs *GameState) addEvent(evt Event) {
	evt.Number = len(gs.Events) + 1
	evt.Time = time.Now().Unix()
	gs.Events = append(gs.Events, evt)
	// Notify any waiting goroutines that the game state
	// has been updated.
	close(gs.changed)
	gs.changed = make(chan struct{})
}

func (gs *GameState) eventsSince(lastSeen int) (evts []Event, next chan struct{}) {
	evts = []Event{}
	for _, e := range gs.Events {
		if e.Number > lastSeen {
			evts = append(evts, e)
		}
	}
	return evts, gs.changed
}

func (g *Game) markSeenWithUser(playerID, name string, team int, when time.Time, userAge string, userGender string, userCountry string, userNativeSpeaker bool) {
	p, ok := g.players[playerID]
	if ok {
		p.LastSeen = when
		if team != 0 && p.Team != team {
			p.Team = team
			g.addEvent(Event{
				Type:              "join_side",
				PlayerID:          playerID,
				Name:              name,
				Team:              team,
				UserAge:           userAge,
				UserGender:        userGender,
				UserCountry:       userCountry,
				UserNativeSpeaker: userNativeSpeaker,
			})
		}
		if name != p.Name && p.Name != "" {
			p.Name = name
			g.addEvent(Event{
				Type:     "change_name",
				PlayerID: playerID,
				Name:     name,
				Team:     team,
			})
		}
		g.players[playerID] = p
		return
	}

	g.players[playerID] = Player{Team: team, Name: name, LastSeen: when}
	if team != 0 {
		g.addEvent(Event{
			Type:              "join_side",
			PlayerID:          playerID,
			Name:              name,
			Team:              team,
			UserAge:           userAge,
			UserGender:        userGender,
			UserCountry:       userCountry,
			UserNativeSpeaker: userNativeSpeaker,
		})
	}
}

func (g *Game) markSeen(playerID, name string, team int, when time.Time) {
	p, ok := g.players[playerID]
	if ok {
		p.LastSeen = when
		if team != 0 && p.Team != team {
			p.Team = team
			g.addEvent(Event{
				Type:     "join_side",
				PlayerID: playerID,
				Name:     name,
				Team:     team,
			})
		}
		if name != p.Name && p.Name != "" {
			p.Name = name
			g.addEvent(Event{
				Type:     "change_name",
				PlayerID: playerID,
				Name:     name,
				Team:     team,
			})
		}
		g.players[playerID] = p
		return
	}

	g.players[playerID] = Player{Team: team, Name: name, LastSeen: when}
	if team != 0 {
		g.addEvent(Event{
			Type:     "join_side",
			PlayerID: playerID,
			Name:     name,
			Team:     team,
		})
	}
}

func (g *Game) guess(playerID, name string, team, index int, rationale string, when time.Time) {
	g.markSeen(playerID, name, team, when)

	// If there's an existing, identical guess event then ignore
	// this guess. Duplicate events may happen if multiple players
	// tap at approximately the same moment.
	for _, e := range g.Events {
		if e.Type == "guess" && e.Index == index && e.Team == team {
			return
		}
	}

	g.addEvent(Event{
		Type:      "guess",
		Team:      team,
		Index:     index,
		PlayerID:  playerID,
		Name:      name,
		Rationale: rationale,
	})
}

func (g *Game) pruneOldPlayers(now time.Time) (remaining int) {
	g.mu.Lock()
	defer g.mu.Unlock()

	for id, player := range g.players {
		if player.LastSeen.Add(50 * time.Second).Before(now) {
			delete(g.players, id)
			if player.Team != 0 {
				g.addEvent(Event{
					Type:     "player_left",
					PlayerID: id,
					Name:     player.Name,
					Team:     player.Team,
				})
			}
			continue
		}
	}
	return len(g.players)
}

func ReconstructGame(state GameState, gameId string) (g Game) {
	g = Game{
		GameState: state,
		OneLayout: make([]Color, len(colorDistribution)),
		TwoLayout: make([]Color, len(colorDistribution)),
		GameID:    gameId,
	}

	rnd := rand.New(rand.NewSource(int64(state.Seed)))

	// Pick 25 random words.
	used := make(map[string]bool, len(colorDistribution))
	for len(used) < len(colorDistribution) {
		w := state.WordSet[rnd.Intn(len(state.WordSet))]
		if !used[w] {
			g.Words = append(g.Words, w)
			used[w] = true
		}
	}

	// Assign the colors for each team, according to the
	// relative distribution in the rule book.
	perm := rnd.Perm(len(colorDistribution))
	for i, colors := range colorDistribution {
		g.OneLayout[perm[i]] = colors[0]
		g.TwoLayout[perm[i]] = colors[1]
	}
	return g
}

var colorDistribution = [25][2]Color{
	{Black, Green},
	{Tan, Green},
	{Tan, Green},
	{Tan, Green},
	{Tan, Green},
	{Tan, Green},
	{Green, Green},
	{Green, Green},
	{Green, Green},
	{Green, Tan},
	{Green, Tan},
	{Green, Tan},
	{Green, Tan},
	{Green, Tan},
	{Green, Black},
	{Tan, Black},
	{Black, Black},
	{Tan, Tan},
	{Tan, Tan},
	{Tan, Tan},
	{Tan, Tan},
	{Tan, Tan},
	{Tan, Tan},
	{Tan, Tan},
	{Black, Tan},
}
