module Backend exposing (..)

import Common exposing (..)
import Lamdera exposing (ClientId, SessionId)
import Time
import Types exposing (..)


type alias Model =
    BackendModel



--noinspection ALL


app =
    Lamdera.backend
        { init = init
        , update = update
        , updateFromFrontend = updateFromFrontend
        , subscriptions = \m -> Lamdera.onConnect (\_ clientId -> SendConnect clientId)
        }


init : ( Model, Cmd BackendMsg )
init =
    ( { playgrounds = seedsPlaygrounds }
    , Cmd.none
    )


seedsPlaygrounds =
    [ { title = "Spielplatz"
      , description = "Dinosaurier Spielplatz am Werder"
      , location = { lat = 52.13078, lng = 11.65262 }
      , id = "525e1b45-6323-44a0-a7ce-981c3965a735"
      , images = []
      , awards =
            [ { title = "Dino"
              , id = "4a98c645-4784-4a6f-b27d-6620d6c1c1eb"
              , found = Just <| Time.millisToPosix 0
              , image =
                    { url = "https://www.trends.de/media/image/f3/6d/05/0258307-001.jpg"
                    , description = "Blauer Dino"
                    }
              }
            , { title = "Dino 2"
              , id = "21f2cd1e-a7f8-46be-8129-358e9c4d3c49"
              , found = Nothing
              , image =
                    { url = "https://stylegreen-shop.cstatic.io/media/image/03/e2/87/styleGREEN_Tierpiktogramm_Dino_Nino_Moostier.png"
                    , description = "Grüner Dino"
                    }
              }
            ]
      }
    , { title = "Spielplatz Schellheimer Platz"
      , description = "Der große Schelli Spielplatz in mitten von Stadtfeld ist mit vielen kleinen Spielsachen bestückt."
      , location = { lat = 52.126787, lng = 11.608743 }
      , id = "38c8d8ed-ad9d-48ca-8d8e-ce37abebdcab"
      , images =
            [ { url = "https://www.magdeburg.de/media/custom/37_45203_1_r.JPG?1602064546"
              , description = "Mittelstelle"
              }
            , { url = "https://bilder.spielplatztreff.de/spielplatzbild/spielplatz-schellheimerplatz-in-magdeburg_1410435124572.jpg"
              , description = "Mittelstelle"
              }
            , { url = "https://www.magdeburg.de/media/custom/37_45203_1_r.JPG?1602064546"
              , description = "Mittelstelle"
              }
            , { url = "https://www.magdeburg.de/media/custom/37_45203_1_r.JPG?1602064546"
              , description = "Mittelstelle"
              }
            ]
      , awards = []
      }
    , { title = "Placeholder"
      , description = "Lorem Ipsum"
      , location = { lat = 52.11, lng = 11.61 }
      , id = "250413dd-ee7c-4889-a1d7-5d4fc9d5c558"
      , images =
            [ { url = "https://www.magdeburg.de/media/custom/37_45203_1_r.JPG?1602064546"
              , description = "Mitteltelle"
              }
            , { url = "https://bilder.spielplatztreff.de/spielplatzbild/spielplatz-schellheimerplatz-in-magdeburg_1410435124572.jpg"
              , description = "Mittelstelle"
              }
            ]
      , awards =
            [ { title = "Dino 3"
              , id = "93ff3df5-970c-4a7b-8064-57904e4c3003"
              , found = Nothing
              , image =
                    { url = "https://www.trends.de/media/image/f3/6d/05/0258307-001.jpg"
                    , description = "Dino Stempel"
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

        SendConnect clientId ->
            ( model, Lamdera.sendToFrontend clientId <| PlaygroundsFetched model.playgrounds )


updateFromFrontend : SessionId -> ClientId -> ToBackend -> Model -> ( Model, Cmd BackendMsg )
updateFromFrontend sessionId clientId msg model =
    case msg of
        NoOpToBackend ->
            ( model, Cmd.none )

        UploadPlayground playground ->
            ( { model | playgrounds = model.playgrounds |> updateListItemViaId playground }, Lamdera.broadcast <| PlaygroundUploaded playground )

        FetchPlaygrounds ->
            ( model, Lamdera.sendToFrontend clientId <| PlaygroundsFetched model.playgrounds )
