port module Game exposing (Model, Msg(..), init, update, viewBoard, viewEvents, viewGuessRationaleModal, viewKeycard, viewStatus, lastEventObj, secondLastEventObj)
import Api exposing (Event, Update)
import Array exposing (Array)
import Browser.Dom as Dom
import Cell exposing (Cell)
import Color exposing (Color)
import Dict
import Html exposing (Html, input, button, div, i, li, span, text, ul, strong)
import Html.Attributes as Attr
import Html.Events exposing (onClick)
import Html.Keyed as Keyed
import Html.Lazy exposing (lazy2, lazy3, lazy5)
import Http
import Player exposing (Player)
import Side exposing (Side)
import Task
import User exposing (User)
import Dialog exposing (Config, view)
import Element exposing (centerY, centerX, rgb)
import Element.Background as Background
import Bootstrap.Alert as Alert exposing (simpleWarning)
import Json.Decode exposing (bool)
import Maybe exposing (withDefault)
import Html.Attributes exposing (name)
import Html.Events exposing (onInput)

port reloadJS : String -> Cmd msg

init : Api.GameState -> User -> Api.Client -> (Msg -> msg) -> ( Model, Cmd msg )
init state user client toMsg =
    let
        model =
            List.foldl applyEvent
                { id = state.id
                , seed = state.seed
                , players = Dict.empty
                , events = []
                , cells =
                    List.map3 (\w l1 l2 -> ( w, ( False, l1 ), ( False, l2 ) ))
                        state.words
                        state.oneLayout
                        state.twoLayout
                        |> List.indexedMap (\i ( w, ( e1, l1 ), ( e2, l2 ) ) -> Cell i w ( e1, l1 ) ( e2, l2 ))
                        |> Array.fromList
                , player = { user = user, side = Nothing }
                , guessesThisTurn = 0
                , chatsThisTurn = 0
                , turn = Nothing
                , tokensConsumed = 0
                , client = client
                , keyView = ShowWords
                , pickedCell = -1
                , modalView = HideModalView
                , clueRationale = ""
                , rationaleError = ""
                }
                state.events

        player =
            { user = user, side = Dict.get user.id model.players }

        modelWithPlayer =
            { model | player = player }
    in
    ( modelWithPlayer, Cmd.batch [ longPollEvents modelWithPlayer toMsg, jumpToBottom "events" toMsg ] )



------ MODEL ------


type alias Model =
    { id : String
    , seed : String
    , players : Dict.Dict String Side
    , events : List Api.Event
    , cells : Array Cell
    , player : Player
    , guessesThisTurn : Int
    , chatsThisTurn: Int
    , turn : Maybe Side
    , tokensConsumed : Int
    , client : Api.Client
    , keyView : KeyView
    , pickedCell : Int
    , modalView : ModalView
    , clueRationale : String
    , rationaleError : String
    }


type KeyView
    = ShowWords
    | ShowKeycard


type Status
    = Start
    | InProgress Side Int Int
    | Lost Int Bool
    | Won Int


lastEvent : Model -> Int
lastEvent m =
    m.events
        |> List.head
        |> Maybe.map (\x -> x.number)
        |> Maybe.withDefault 0

lastEventObj : Model -> Event
lastEventObj m =
    m.events
        |> List.head
        |> Maybe.withDefault (Event 0 "" "" "" (Just Side.A) 0 (Array.repeat 1 "") 0 "" "" True "" "")

secondLastEventObj : Model -> Event
secondLastEventObj m =
    m.events
        |> List.drop 1 
        |> List.head
        |> Maybe.withDefault (Event 0 "" "" "" (Just Side.B) 0 (Array.repeat 1 "") 0 "" "" True "" "")

status : Model -> Status
status g =
    let
        greens =
            remainingGreen g.cells
    in
    case g.turn of
        Nothing ->
            Start

        Just turn ->
            if exposedBlack <| Array.toList <| g.cells then
                Lost greens False

            else if greens == 0 then
                Won g.tokensConsumed

            else if g.tokensConsumed > 9 then
                Lost greens True

            else
                InProgress turn greens g.tokensConsumed


remainingGreen : Array Cell -> Int
remainingGreen cells =
    15
        - (cells
            |> Array.map Cell.display
            |> Array.filter (\x -> x == Cell.ExposedGreen)
            |> Array.length
          )


exposedBlack : List Cell -> Bool
exposedBlack cells =
    cells
        |> List.map Cell.display
        |> List.any (\x -> x == Cell.ExposedBlack)


hasHiddenGreens : Side -> Array Cell -> Bool
hasHiddenGreens side cells =
    cells
        |> Array.toList
        |> List.filter (\x -> Cell.display x /= Cell.ExposedGreen)
        |> List.any (\x -> Cell.sideColor side x == Color.Green)



------ UPDATE ------


type Msg
    = NoOp
    | LongPoll String String (Result Http.Error Api.Update)
    | GameUpdate (Result Http.Error Api.Update)
    | WordPicked Cell
    | ToggleModalView ModalView
    | ToggleKeyView KeyView
    | GuessRationaleChanged String
    | SubmitGuess Int
    | DoneGuessing
    | ReloadPage

type ModalView 
    = ShowModalView
    | HideModalView


update : Msg -> Model -> (Msg -> msg) -> Maybe ( Model, Cmd msg )
update msg model toMsg =
    case msg of

        ReloadPage -> Just (model, reloadJS "reload")

        NoOp ->
            Just ( model, Cmd.none )

        LongPoll id seed result ->
            case ( id == model.id && seed == model.seed, result ) of
                ( False, _ ) ->
                    -- We might get the result of a long poll from a previous
                    -- game we were playing, in which case we just want to
                    -- ignore it.
                    Just ( model, Cmd.none )

                ( True, Err e ) ->
                    -- Even if the long poll request failed for some reason,
                    -- we want to trigger a new request anyways. The failure
                    -- could be short-lived.
                    -- TODO: add exponential backoff
                    Just ( model, longPollEvents model toMsg )

                ( True, Ok up ) ->
                    applyUpdate model up toMsg
                        |> Maybe.map (\( m, cmd ) -> ( m, Cmd.batch [ cmd, longPollEvents m toMsg ] ))

        GameUpdate (Ok up) ->
            applyUpdate model up toMsg

        GameUpdate (Err err) ->
            -- TODO: flash an error message? 
            Just ( model, Cmd.none )

        ToggleKeyView newSetting ->
            Just ( { model | keyView = newSetting }, Cmd.none )

        WordPicked cell ->
            case model.player.side of
                Nothing ->
                    Just ( model, Cmd.none )

                Just side ->
                    if not (Cell.isExposed (Side.opposite side) cell) then
                        Just ({ model | modalView = ShowModalView, pickedCell = cell.index, clueRationale = "", rationaleError = "" }, Cmd.none)
                    else 
                        Just (model, Cmd.none) 

        SubmitGuess index ->
            if index < 0 then
                Just (model, Cmd.none)
            else
                case (List.length (String.words model.clueRationale) < 3, Array.get index model.cells, model.player.side) of 
                    (True, _, _) -> 
                        Just ({ model | rationaleError = "Rationale must have more than 3 words!"}, Cmd.none)
                    (False, Just cell, Just side) ->
                        Just
                            ( { model | modalView = HideModalView, pickedCell = -1, clueRationale = "" }
                            , if not (Cell.isExposed (Side.opposite side) cell) then
                                Api.submitGuess
                                    { gameId = model.id
                                    , seed = model.seed
                                    , player = model.player
                                    , index = cell.index
                                    , lastEventId = lastEvent model
                                    , toMsg = \x -> toMsg (GameUpdate x)
                                    , client = model.client
                                    , rationale = model.clueRationale
                                    }
                            else
                                Cmd.none
                            )
                    (_, _, _) ->
                        Just (model, Cmd.none)

        DoneGuessing ->
            case ( model.turn, model.turn == model.player.side ) of
                ( Just side, True ) ->
                    Just
                        ( model
                        , Api.endTurn
                            { gameId = model.id
                            , seed = model.seed
                            , player = model.player
                            , toMsg = always (toMsg NoOp)
                            , client = model.client
                            }
                        )

                _ ->
                     Just ( model, Cmd.none )

        ToggleModalView newSetting -> 
            Just ( { model | modalView = newSetting }, Cmd.none )

        GuessRationaleChanged newRationale ->
            Just ( { model | clueRationale = newRationale}, Cmd.none) 


applyUpdate : Model -> Update -> (Msg -> msg) -> Maybe ( Model, Cmd msg )
applyUpdate model up toMsg =
    if up.seed /= model.seed then
        -- If the seed doesn't match, the previous game was destroyed
        -- and replaced with a new game.
        Nothing

    else
        let
            newModel =
                List.foldl applyEvent model up.events
        in
        Just
            ( newModel
            , if lastEvent newModel > lastEvent model then
                jumpToBottom "events" toMsg

              else
                Cmd.none
            )


applyEvent : Event -> Model -> Model
applyEvent e model =
    if e.number <= lastEvent model then
        model

    else
        case e.typ of
            "join_side" ->
                { model | players = Dict.update e.playerId (\_ -> e.side) model.players, events = e :: model.events }

            "player_left" ->
                { model | players = Dict.update e.playerId (\_ -> Nothing) model.players, events = e :: model.events }

            "guess" ->
                case ( Array.get e.index model.cells, e.side ) of
                    ( Just cell, Just side ) ->
                        applyGuess e cell side model

                    _ ->
                        { model | events = e :: model.events }

            "end_turn" ->
                case ( model.turn == e.side, e.side ) of
                    ( True, Just side ) ->
                        { model
                            | turn =
                                if hasHiddenGreens side model.cells then
                                    Just (Side.opposite side)

                                else
                                    model.turn
                            , guessesThisTurn = 0
                            , chatsThisTurn = 0
                            , tokensConsumed = model.tokensConsumed + 1
                            , events = e :: model.events
                        }

                    _ ->
                        { model | events = e :: model.events }

            _ ->
                { model | events = e :: model.events }


applyGuess : Event -> Cell -> Side -> Model -> Model
applyGuess e cell side model =
    if model.turn == Just (Side.opposite side) then
        -- It's not this side's turn to guess.
        -- Ignore it.
        { model | events = e :: model.events }

    else
        let
            updatedCells =
                Array.set e.index (Cell.tapped side cell) model.cells
        in
        case Cell.oppColor side cell of
            Color.Tan ->
                -- When a tan is tapped, a token is always consumed.
                -- We only flip the turn if side that guessed the tan
                -- also has unrevealed greens for the other side to guess.
                { model
                    | cells = updatedCells
                    , events = e :: model.events
                    , turn =
                        if hasHiddenGreens side updatedCells then
                            Just (Side.opposite side)

                        else
                            Just side
                    , guessesThisTurn = 0
                    , chatsThisTurn = 0
                    , tokensConsumed = model.tokensConsumed + 1
                }

            Color.Green ->
                -- When a green is tapped, it might be the last green on
                -- the opposite side's board, in which case we need to
                -- consume a token and flip the turn.
                if hasHiddenGreens (Side.opposite side) updatedCells then
                    { model
                        | cells = updatedCells
                        , events = e :: model.events
                        , guessesThisTurn = model.guessesThisTurn + 1
                        , turn = Just side
                    }

                else
                    { model
                        | cells = updatedCells
                        , events = e :: model.events
                        , turn = Just (Side.opposite side)
                        , guessesThisTurn = 0
                        , tokensConsumed = model.tokensConsumed + 1
                    }

            Color.Black ->
                -- game over
                { model | cells = updatedCells, events = e :: model.events }


longPollEvents : Model -> (Msg -> msg) -> Cmd msg
longPollEvents m toMsg =
    Api.longPollEvents
        { gameId = m.id
        , seed = m.seed
        , player = m.player
        , lastEventId = lastEvent m
        , tracker = m.id ++ m.seed
        , toMsg = \x -> toMsg (LongPoll m.id m.seed x)
        , client = m.client
        }



------ VIEW ------


jumpToBottom : String -> (Msg -> msg) -> Cmd msg
jumpToBottom id toMsg =
    Dom.getViewportOf id
        |> Task.andThen (\info -> Dom.setViewportOf id 0 info.scene.height)
        |> Task.attempt (always (toMsg NoOp))


viewStatus : Model -> Html Msg
viewStatus model =
    case status model of
        Start ->
            if ((Dict.size model.players) < 2) then
                div [ Attr.id "status", Attr.class "in-progress" ]
                    [ div [] [ text "Please wait for another player to join the other side!" ] ]
            else if ((lastEventObj model).typ == "chat") then
                if (lastEventObj model).side == model.player.side then
                    div [ Attr.id "status", Attr.class "in-progress" ]
                        [ 
                            div [] [ text "You gave the first hint! The other side is now guessing, so it's your turn to wait. If you wait longer than two minutes without a response, a button will pop up and you can request a new player!" ]
                            , div [] [ button [ Attr.class "done-guessing", Attr.class "hidden-button inactive-button", onClick ReloadPage ] [ text "Restart if you think opponent is inactive." ] ]
                        ]
                else
                    div [ Attr.id "status", Attr.class "in-progress" ]
                        [ div [] [ text "The other player gave the first hint! Tap on words on the left to guess." ] ]                  
            else
                div [ Attr.id "status", Attr.class "in-progress" ]
                    [ 
                        div [] [ text "Players have joined both sides. Either side may give the first clue! No side can start guessing until the other side has sent a clue in the chatbox. After the initial clue, if you wait longer than two minutes without a response, a button will pop up and you can request a new player!" ] 
                    ]     
            
        Lost _ False ->
            div [] [ div [ Attr.id "status", Attr.class "lost" ]
                [ div [] [ 
                    text "You guessed a black word and lost :( If you want, you can hit the button and play another page. We'll regenerate the 3 lines to copy into MTurk." ]
                , div [  Attr.style "padding" "8px"  ] [ strong [] [ text "Please make sure you save the lines from the current game, so you can copy all your games into MTurk!" ] ]
                , div [] [ button [ Attr.class "done-guessing", onClick ReloadPage ] [ text "Do you want to play another game? Click here!" ] ]
                ]
                ,div [] [
                 div [] [ text ("Please copy the following 3 lines into MTurk when you are done!") ] 
                , div [] [ text ("Your Username is: " ++ model.player.user.name) ] 
                , div [] [ text ("Your User ID is: " ++ model.player.user.id) ] 
                , div [] [ text ("Your Game ID is: " ++ model.id) ] 
                ] 
            ]

        Lost _ True ->
            div [] [ div [ Attr.id "status", Attr.class "lost" ]
                [ div [] [ 
                    text "You ran out of timer tokens and lost :( If you want, you can hit the button and play another page. We'll regenerate the 3 lines to copy into MTurk." ]
                , div [  Attr.style "padding" "8px"  ] [ strong [] [ text "Please make sure you save the lines from the current game, so you can copy all your games into MTurk!" ] ]
                , div [] [ button [ Attr.class "done-guessing", onClick ReloadPage ] [ text "Do you want to play another game? Click here!" ] ]
                 ] 
                , div [] [
                div [] [ text ("Please copy the following 3 lines into MTurk when you are done!") ] 
                , div [] [ text ("Your Username is: " ++ model.player.user.name) ] 
                , div [] [ text ("Your User ID is: " ++ model.player.user.id) ] 
                , div [] [ text ("Your Game ID is: " ++ model.id) ] 
                ]
            ]

        Won _ ->
            div [] [ div [ Attr.id "status", Attr.class "won" ]
                [ div [] [ text "You won! If you want, you can hit the button and play another page. We'll regenerate the 3 lines to copy into MTurk." ] 
                , div [] [ text ("Please copy the following 3 lines into MTurk when you are done!") ] 
                , div [] [ button [ Attr.class "done-guessing", onClick ReloadPage ] [ text "Do you want to play another game? Click here!" ] ]] 
                , div [  Attr.style "padding" "8px"  ] [ strong [] [ text "Please make sure you save the lines from the current game, so you can copy all your games into MTurk!" ] ]
                , div [] [
                div [] [ text ("Your Username is: " ++ model.player.user.name) ] 
                , div [] [ text ("Your User ID is: " ++ model.player.user.id) ] 
                , div [] [ text ("Your Game ID is: " ++ model.id) ] 
                ]]

        InProgress turn greens tokensConsumed ->
            div [] [ div [ Attr.id "status", Attr.class "in-progress" ]
                (List.append
                    (if Just turn == model.player.side then
                        div [] [ text "You're guessing. If you cannot click on any of the words on the board yet, please wait for the other side to send a clue in the chatbox first." ]
                            :: (if model.guessesThisTurn > 0 then
                                    -- You /must/ guess at least once.
                                    [ div [] [ button [ Attr.class "done-guessing", onClick DoneGuessing ] [ text "Done guessing" ] ] ]

                                else
                                    [ div [] [ button [ Attr.class "done-guessing", Attr.disabled True ] [ text "Must guess once" ] ] ]
                               )

                     else
                        [ div [] [ text "You're clue giving. The other side cannot start guessing until you send a clue in the chatbox." ] ]
                    )
                    [ div [] [ text (String.fromInt greens), span [ Attr.class "green-icon" ] [] ]
                    , div [] [ text (String.fromInt tokensConsumed), text " ", i [ Attr.class "icon ion-ios-time" ] [] ]
                    , div [ Attr.style "text-align" "center" ] [ button [ Attr.class ((Side.toString turn) ++ "-hidden-button inactive-button"), onClick ReloadPage ] [ text ( "Restart if you think opponent is inactive." ) ] ]
                    ]
                ) ]


viewBoard : Model -> Html Msg
viewBoard model =
    let
        isGuessing =
            model.turn == model.player.side || model.turn == Nothing

        tapMsg =
            if isGuessing then
                WordPicked

            else
                always NoOp
    in
    Keyed.node "div"
        [ Attr.id "board"
        , Attr.classList
            [ ( "no-team", model.player.side == Nothing )
            , ( "guessing", isGuessing )
            ]
        ]
        (model.cells
            |> Array.toList
            |> List.map (\c -> ( c.word, lazy5 Cell.view model.player.side (((lastEventObj model).side == Just (Side.opposite (Maybe.withDefault Side.A (model.player.side))) && (lastEventObj model).typ == "chat") 
    || (List.length model.events >= 2
    && (secondLastEventObj model).side == Just (Side.opposite (Maybe.withDefault Side.A (model.player.side))) 
    && (secondLastEventObj model).typ == "chat" 
    && (lastEventObj model).side == Just (Side.opposite (Maybe.withDefault Side.A (model.player.side))) 
    && (lastEventObj model).typ == "end_turn") || ((lastEventObj model).side == model.turn && (lastEventObj model).typ == "guess")) ((lastEventObj model).typ == "join_side") tapMsg c ))
        )


viewEvents : Model -> Html Msg
viewEvents model =
    Keyed.node "div"
        [ Attr.id "events" ]
        (( "Welcome", viewWelcomeMessage model )
            :: (model.events
                    |> List.reverse
                    |> List.map (\e -> ( String.fromInt e.number, lazy2 viewEvent model e ))
               )
        )


viewWelcomeMessage : Model -> Html Msg
viewWelcomeMessage model =
    div [] [ div [ Attr.class "system-message" ] [ text """
    Welcome! Codenames Green is a cooperative word game. Players divide into
    two sides. Each side has nine green words that they must provide clues for.
    Sides take turns giving one-word clues, and the target words on the board 
    that it applies to according to the cluegiver. Then the other side guesses until they tap
    a non-green word or choose to stop. Tapping a black instantly loses the game.
    Try to reveal all green words before the timer counter reaches 9.
    Good luck, have fun!
    """ ]
    ]

config e =
    { closeMessage = Nothing
    , maskAttributes = []
    , headerAttributes = []
    , bodyAttributes = []
    , footerAttributes = []
    , containerAttributes =
        [ Background.color (rgb 1 0 0)
        , centerX
        , centerY
        ]
    , header = Just (Element.text "Invalid Chat Input")
    , body = e.error_message
    , footer = Nothing
    }

viewEvent : Model -> Event -> Html Msg
viewEvent model e =
    case e.typ of
        "join_side" ->
            div [] [
                div [] [text e.name
                    , text " has joined side "
                    , text (e.side |> Maybe.map Side.toString |> Maybe.withDefault "")
                    , text "."
                ]
                , div [] [ text ("Side ")
                , text (e.side |> Maybe.map Side.toString |> Maybe.withDefault "")
                , text ("'s demographic information is as follows: ") ]
                , div [] [text (String.fromChar (Char.fromCode 8195)), text (String.fromChar (Char.fromCode 8195)), strong [] [text ("Age : " ++ e.user_age)]] 
                , div [] [text (String.fromChar (Char.fromCode 8195)), text (String.fromChar (Char.fromCode 8195)), strong [] [text ("Gender : " ++ e.user_gender)]] 
                , div [] [text (String.fromChar (Char.fromCode 8195)), text (String.fromChar (Char.fromCode 8195)), strong [] [text ("Country of Origin : " ++ e.user_country)]] 
                , div [] [text (String.fromChar (Char.fromCode 8195))
                        , text (String.fromChar (Char.fromCode 8195))
                        , strong [] [text (if e.user_native_speaker then "They DO identify as a Native English speaker" else "They DO NOT identify as a Native English speaker") ]] 

            ]

        "player_left" ->
            div [] [ text e.name, text " has left the game." ]

        "guess" ->
            Array.get e.index model.cells
                |> Maybe.map2
                    (\s c ->
                        div []
                            [ text "Side "
                            , text (Side.toString s)
                            , text " tapped "
                            , span [ Attr.class "chat-color", Attr.class (Color.toString (Cell.oppColor s c)) ] [ text c.word ]
                            , text "."
                            ]
                    )
                    e.side
                |> Maybe.withDefault (text "")

        "chat" ->
            let
                sideEl =
                    case e.side of
                        Just s ->
                            span [ Attr.class "side" ] [ text (" (" ++ Side.toString s ++ ")") ]

                        Nothing ->
                            text ""
            in
            div [] [ text e.name, sideEl, text ": ", text (Maybe.withDefault "" (Array.get 0 e.message)), text ", ", text (String.fromInt e.num_target_words) ]

        "end_turn" ->
            case e.side of
                Nothing ->
                    text ""

                Just side ->
                    div [] [ text "Side ", text (Side.toString side), text " took a timer token ending the turn." ]

        "chat_error" ->
            -- Element.layout [] <|
            --     Dialog.view (Just config)
            if e == (lastEventObj model) && e.side == model.player.side then 
                div [ 
                    Attr.style "border" "red",
                    Attr.style "border-style" "solid",
                    Attr.style "border-radius" "10px",
                    Attr.style "padding-left" "5px",
                    Attr.style "padding-right" "5px"
                ] [ div [ Attr.style "color" "red", Attr.style "font-size" "15px"] [text "Invalid Chat Input"]
                , div [ Attr.style "color" "red", Attr.style "font-size" "12px"] [text e.error_message ] ]
            else text ""       
        _ ->
            text ""



viewGuessRationaleModal : Model -> Html Msg
viewGuessRationaleModal model = 
    case model.modalView of 
        ShowModalView ->

            let
                res = case (Array.get model.pickedCell model.cells) of
                    Just val ->
                        val.word
                    Nothing -> 
                        ""
            in
                div [ Attr.class "modal" ] [ 
                    div [ Attr.class "modal-content" ] [
                        if (String.length model.rationaleError) == 0 then div [] [] else div [] [ text "Please enter more than 3 words for the rationale." ] 
                        , div [] [ text ("You picked " ++ res ++ ". Please enter your reasoning based on the clue.")]
                        , div [] [ text "Rationale " , input [ Attr.value model.clueRationale, onInput (GuessRationaleChanged)] []]

                        , button [ onClick (SubmitGuess model.pickedCell) ] [ text "Submit Guess" ]
                        , button [ onClick (ToggleModalView HideModalView) ] [ text "Cancel" ]
                    ] 
                ]
        HideModalView ->
            div [] []

viewKeycard : Model -> Side -> Html Msg
viewKeycard model side =
    div [ Attr.id "key" ]
        [ case model.keyView of
            ShowWords ->
                let
                    cells =
                        Array.toList model.cells

                    cellsOf =
                        \color -> List.filter (\c -> Cell.sideColor side c == color) cells
                in
                div [ Attr.id "key-list", onClick (ToggleKeyView ShowKeycard) ]
                    [ ul [ Attr.class "greens" ]
                        (cellsOf Color.Green
                            |> List.map (\x -> li [ Attr.classList [ ( "crossed", Cell.isExposedAll x ) ] ] [ text x.word ])
                        )
                    , ul [ Attr.class "blacks" ]
                        (cellsOf Color.Black
                            |> List.map (\x -> li [ Attr.classList [ ( "crossed", Cell.isExposed side x || Cell.isExposedAll x ) ] ] [ text x.word ])
                        )
                    , ul [ Attr.class "tans" ]
                        (cellsOf Color.Tan
                            |> List.take 7
                            |> List.map (\x -> li [ Attr.classList [ ( "crossed", Cell.isExposed side x || Cell.isExposedAll x ) ] ] [ text x.word ])
                        )
                    , ul [ Attr.class "tans" ]
                        (cellsOf Color.Tan
                            |> List.drop 7
                            |> List.map (\x -> li [ Attr.classList [ ( "crossed", Cell.isExposed side x || Cell.isExposedAll x ) ] ] [ text x.word ])
                        )
                    ]

            ShowKeycard ->
                div [ Attr.id "key-card", onClick (ToggleKeyView ShowWords) ]
                    (model.cells
                        |> Array.toList
                        |> List.map
                            (\c ->
                                div
                                    [ Attr.classList
                                        [ ( "cell", True )
                                        , ( Color.toString <| Cell.sideColor side <| c, True )
                                        , ( "crossed", Cell.isExposed side c || Cell.isExposedAll c )
                                        ]
                                    ]
                                    []
                            )
                    )
        ]
