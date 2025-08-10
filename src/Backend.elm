module Backend exposing (..)

import Common exposing (..)
import Dict
import Http
import IdSet
import Json.Decode as D
import Lamdera exposing (ClientId, SessionId)
import Types exposing (..)


type alias Model =
    BackendModel



--noinspection ElmUnusedSymbol,ElmReview


app =
    Lamdera.backend
        { init = init
        , update = update
        , updateFromFrontend = updateFromFrontend
        , subscriptions =
            \_ ->
                Sub.batch
                    [ Lamdera.onConnect ClientConnected
                    , Lamdera.onDisconnect (\_ clientId -> ClientDisconnected clientId)
                    ]
        }


init : ( BackendModel, Cmd BackendMsg )
init =
    ( { playgrounds = IdSet.fromList seedsPlaygrounds
      , connections = IdSet.empty
      , users = IdSet.empty
      , deleteHashes = Dict.empty |> Dict.insert "https://i.imgur.com/kZbTHiA.png" "VNqYAk7BQvBJ3wU"
      }
    , Cmd.none
    )


seedsPlaygrounds : List Playground
seedsPlaygrounds =
    [ { title = "Spielplatz"
      , description = "Dinosaurier Spielplatz am Werder"
      , location = { lat = 52.13078, lng = 11.65262 }
      , id = "525e1b45-6323-44a0-a7ce-981c3965a735"
      , images = []
      , markerIcon = defaultMarkerIcon
      , awards =
            [ { title = "Dino"
              , id = "4a98c645-4784-4a6f-b27d-6620d6c1c1eb"
              , image =
                    { url = "https://i.imgur.com/kZbTHiA.png"
                    }
              }
            , { title = "Dino 2"
              , id = "21f2cd1e-a7f8-46be-8129-358e9c4d3c49"
              , image =
                    { url = "https://stylegreen-shop.cstatic.io/media/image/03/e2/87/styleGREEN_Tierpiktogramm_Dino_Nino_Moostier.png"
                    }
              }
            ]
      }
    , { title = "Spielplatz Schellheimer Platz"
      , description = "Der große Schelli Spielplatz in mitten von Stadtfeld ist mit vielen kleinen Spielsachen bestückt."
      , location = { lat = 52.126787, lng = 11.608743 }
      , id = "38c8d8ed-ad9d-48ca-8d8e-ce37abebdcab"
      , markerIcon = defaultMarkerIcon
      , images =
            [ { url = "https://www.magdeburg.de/media/custom/37_45203_1_r.JPG?1602064546"
              }
            , { url = "https://bilder.spielplatztreff.de/spielplatzbild/spielplatz-schellheimerplatz-in-magdeburg_1410435124572.jpg"
              }
            , { url = "https://www.magdeburg.de/media/custom/37_45203_1_r.JPG?1602064546"
              }
            , { url = "https://www.magdeburg.de/media/custom/37_45203_1_r.JPG?1602064546"
              }
            ]
      , awards = []
      }
    , { title = "Placeholder"
      , description = "Lorem Ipsum"
      , location = { lat = 52.11, lng = 11.61 }
      , id = "250413dd-ee7c-4889-a1d7-5d4fc9d5c558"
      , markerIcon = defaultMarkerIcon
      , images =
            [ { url = "https://www.magdeburg.de/media/custom/37_45203_1_r.JPG?1602064546"
              }
            , { url = "https://bilder.spielplatztreff.de/spielplatzbild/spielplatz-schellheimerplatz-in-magdeburg_1410435124572.jpg"
              }
            ]
      , awards =
            [ { title = "Dino 3"
              , id = "93ff3df5-970c-4a7b-8064-57904e4c3003"
              , image =
                    { url = "https://www.trends.de/media/image/f3/6d/05/0258307-001.jpg"
                    }
              }
            ]
      }
    ]


update : BackendMsg -> Model -> ( Model, Cmd BackendMsg )
update msg model =
    case msg of
        NoOpBackendMsg ->
            ( model, Cmd.none )

        ClientConnected _ clientId ->
            -- let
            -- possibleUser =
            --     model.users |> IdSet.toList |> List.filter (\u -> u.sessions |> Set.member sessionId) |> List.head
            -- TOOD was machen? Soll die UserId auf dem client generiert werden?
            -- Wie wird die session erstellt?
            -- Hier oder wo anders?
            -- user =
            --     case possibleUser of
            --         Just user_ ->
            --             user_
            --         Nothing ->
            --             {
            --             }
            -- in
            ( { model | connections = model.connections |> IdSet.insert (initConnection clientId) }
            , Cmd.batch
                [ Lamdera.sendToFrontend clientId <|
                    PlaygroundsFetched <|
                        IdSet.toList <|
                            model.playgrounds
                , Lamdera.sendToFrontend clientId (DeleteHashUpdated model.deleteHashes)
                ]
            )

        ClientDisconnected clientId ->
            ( { model | connections = model.connections |> IdSet.remove clientId }, Cmd.none )



-- ImageUploaded result ->
--     let
--         _ =
--             Debug.log "image upload result" result
--     in
--     ( model, Cmd.none )


initConnection : ClientId -> Connection
initConnection clientId =
    { id = clientId, userId = Nothing }


updateFromFrontend : SessionId -> ClientId -> ToBackend -> Model -> ( Model, Cmd BackendMsg )
updateFromFrontend sessionId clientId msg model =
    let
        others =
            model.connections |> IdSet.remove clientId |> IdSet.toList |> List.map .id
    in
    case msg of
        NoOpToBackend ->
            ( model, Cmd.none )

        UploadPlayground playground ->
            ( { model | playgrounds = model.playgrounds |> IdSet.insert playground }, broadcastTo others <| PlaygroundUploaded playground )

        RemovePlayground playground ->
            ( { model | playgrounds = model.playgrounds |> IdSet.remove playground.id }, broadcastTo others <| PlaygroundRemoved playground )

        -- This gets called before SetConnectedUser
        Collect itemId ->
            let
                maybeAward =
                    allAwards model.playgrounds
                        |> List.filter (\a -> a.id == itemId)
                        |> List.head

                maybeUser =
                    model.connections
                        |> IdSet.get clientId
                        |> Maybe.andThen .userId
                        |> Maybe.andThen (\userId -> model.users |> IdSet.get userId)
            in
            case ( maybeAward, maybeUser ) of
                ( Just award, Just user ) ->
                    let
                        newUser =
                            { user | awards = user.awards |> IdSet.insert award }

                        userConnections =
                            model.connections
                                |> IdSet.toList
                                |> List.filter (\{ userId } -> userId == Just newUser.id)
                                |> List.map .id
                    in
                    ( { model | users = model.users |> IdSet.insert newUser }
                    , broadcastTo userConnections <| UserUpdated newUser
                    )

                _ ->
                    ( model, Cmd.none )

        SetConnectedUser guid ->
            let
                ( users, user ) =
                    model.users |> IdSet.getOrInsert guid (initUser guid)

                connected =
                    model.connections |> IdSet.insert { id = clientId, userId = Just user.id }
            in
            ( { model | users = users, connections = connected }, Cmd.batch [ Lamdera.sendToFrontend clientId <| UserUpdated user, Lamdera.sendToFrontend clientId UserLoggedIn ] )

        UploadImage file ->
            ( model, Cmd.none )

        AddDeleteHash link hash ->
            let
                hashes =
                    model.deleteHashes |> Dict.insert link hash
            in
            ( { model | deleteHashes = hashes }, Lamdera.broadcast (DeleteHashUpdated hashes) )



-- imageUploadCmd file


initUser : Guid -> User
initUser id =
    { id = id, awards = IdSet.empty }


broadcastTo clientIds msg =
    clientIds |> List.map (\id -> Lamdera.sendToFrontend id msg) |> Cmd.batch



-- imageUploadCmd file =
--     Http.post
--         { url = "https://api.imgur.com/3/image"
--         , expect = Http.expectJson ImageUploaded (D.value |> D.map Debug.toString)
--         , body =
--             Http.multipartBody
--                 [ Http.stringPart "type" "image"
--                 , Http.stringPart "title" "some title"
--                 , Http.stringPart "description" "some description"
--                 , Http.bytesPart "image" "image/png" file
--                 ]
--         }
