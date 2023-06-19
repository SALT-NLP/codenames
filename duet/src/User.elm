port module User exposing (User, decode, store)

import Json.Decode as D
import Json.Encode as E


port storeCache : E.Value -> Cmd msg


{-| A user holds persisted user preferences.

It's stored in local storage, and is used to
keep settings like the player's name between
sessions.

-}
type alias User =
    { id : String
    , name : String
    , native_speaker : Bool
    , country: String
    , gender: String
    , age: String
    }


store : User -> Cmd msg
store user =
    user
        |> encode
        |> storeCache


decode : D.Value -> Result D.Error User
decode value =
    D.decodeValue D.string value
        |> Result.andThen (D.decodeString decoder)


encode : User -> E.Value
encode user =
    E.object
        [ ( "player_id", E.string user.id )
        , ( "name", E.string user.name )
        , ( "native_speaker", E.bool user.native_speaker )

        , ( "country", E.string user.country )
        , ( "gender", E.string user.gender )
        , ( "age", E.string user.age )
        ]


decoder : D.Decoder User
decoder =
    D.map6 User
        (D.field "player_id" D.string)
        (D.field "name" D.string)
        (D.field "native_speaker" D.bool)
        (D.field "country" D.string)
        (D.field "gender" D.string)
        (D.field "age" D.string)
