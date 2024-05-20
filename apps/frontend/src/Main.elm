port module Main exposing (main)

import Browser
import Browser.Navigation as Nav
import Element exposing (..)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Html
import Html.Attributes
import Html.Events exposing (onClick, onInput)
import Http
import Json.Decode as JD
import Json.Encode as JE
import Material.Icons as Icons
import Material.Icons.Types exposing (Icon)
import Url



-- MAIN


main : Program () Model Msg
main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , onUrlChange = UrlChanged
        , onUrlRequest = LinkClicked
        }



-- MODEL


type alias Model =
    { key : Nav.Key
    , url : Url.Url
    , capture : String
    , message : String
    , online : Bool
    }


init : () -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init _ url key =
    ( Model key url "" "" True, Cmd.none )



-- UPDATE


type Msg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url
    | Capture String
    | CreateCapture
    | SaveCaptureResult (Result Http.Error String)
    | Online Bool


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        LinkClicked urlRequest ->
            case urlRequest of
                Browser.Internal url ->
                    ( model, Nav.pushUrl model.key (Url.toString url) )

                Browser.External href ->
                    ( model, Nav.load href )

        UrlChanged url ->
            ( { model | url = url }
            , Cmd.none
            )

        Capture text ->
            ( { model | capture = text }, Cmd.none )

        CreateCapture ->
            ( model, saveCapture model.online model.capture )

        SaveCaptureResult (Ok response) ->
            ( { model | capture = "", message = "Capture saved" }, Cmd.none )

        SaveCaptureResult (Err e) ->
            ( { model | message = "The capture couldn't be saved" }, Cmd.none )

        Online status ->
            ( { model | online = status }, Cmd.none )



-- SUBSCRIPTIONS


port online : (Bool -> msg) -> Sub msg


port pouchDB : String -> Cmd msg


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch [ online Online ]



-- VIEW


view : Model -> Browser.Document Msg
view model =
    { title = "DWYL App"
    , body =
        [ Html.node "link" [ Html.Attributes.rel "stylesheet", Html.Attributes.href "https://fonts.googleapis.com/css?family=Itim" ] []
        , layout [ width fill, height fill, inFront <| el [ alignBottom, alignRight, padding 32 ] <| buttonAwards ] <|
            column [ width fill, height fill, spacing 32, padding 22, scrollbarY ]
                [ column [ spacing 16, width fill ]
                    [ placeholderLarger
                    , linePlaceholder 8
                    , linePlaceholder 2
                    ]
                , mapPlaceholder
                , column
                    [ spacing 16, width fill ]
                    [ playgroundItemPlaceholder 3
                    , playgroundItemPlaceholder 4.2
                    , playgroundItemPlaceholder 4.5
                    , playgroundItemPlaceholder 4.5
                    , playgroundItemPlaceholder 4.5
                    , playgroundItemPlaceholder 4.5
                    ]
                ]

        -- main_ [ class "pa2" ]
        --     [ text model.message
        --     , onlineView model.online
        --     , h1 [ class "tc " ] [ text "Capture" ]
        --     , div [ class "h-75" ]
        --         [ textarea
        --             [ onInput Capture
        --             , value model.capture
        --             , class "db mb2 center w-100 w-60-l h-100 resize-none"
        --             , placeholder "write down everything that is on your mind"
        --             ]
        --             []
        --         , text "hello world"
        --         , div [ class "tc" ]
        --             [ button [ class "bg-near-white bn", onClick CreateCapture ]
        --                 [ img [ class "pointer tc center", src "/assets/images/submit.png", alt "capture" ] []
        --                 ]
        --             ]
        --         ]
        --     ]
        ]
    }


linePlaceholder space =
    row [ width fill ]
        [ placeholder
        , el [ width (px (space * 8)) ] <| none
        ]


placeholder =
    el [ Border.rounded 16, Background.color grayLight, width fill, height (px 36) ] <| none


placeholderLarger =
    el [ Border.rounded 16, Background.color grayDark, width fill, height (px 48) ] <| none


grayLight =
    rgb255 224 231 236


grayDark =
    rgb255 148 162 171


white =
    rgb 1 1 1


mapPlaceholder =
    el
        [ Border.rounded 16
        , Background.color grayLight
        , width fill
        , square
        , flexBasisAuto
        ]
    <|
        el [ centerX, centerY, itim, Font.color grayDark ] <|
            text "map"


playgroundItemPlaceholder km =
    el
        [ Border.rounded 16
        , Background.color grayLight
        , width fill
        , height (px 64)
        , paddingXY 24 0
        ]
    <|
        row [ centerY, width fill, Font.color grayDark ]
            [ materialIcon Icons.local_play
            , el [ alignRight, itim, Font.size 24 ] <|
                text <|
                    (String.fromFloat km ++ "km")
            ]


buttonAwards =
    el [ Background.color grayDark, Border.rounded 999, padding 16, scale 1.5, Font.color white, Border.shadow { offset = ( 0, 4 ), size = 0, blur = 18, color = rgba 0 0 0 0.25 } ] <| materialIcon Icons.approval


square =
    htmlAttribute <| Html.Attributes.style "aspect-ratio" "1/1"


flexBasisAuto =
    htmlAttribute <| Html.Attributes.style "flex-basis" "auto"


itim =
    Font.family [ Font.typeface "Itim" ]


materialIcon : Icon msg -> Element msg
materialIcon icon =
    el [] <| html <| icon 24 Material.Icons.Types.Inherit



-- onlineView : Bool -> Html.Html Msg
-- onlineView onlineStatus =
--     div [ classList [ ( "dn", onlineStatus ) ] ]
--         [ img [ src "/assets/images/signal_wifi_off.svg", alt "offline icon" ] []
--         ]
-- Capture


saveCapture : Bool -> String -> Cmd Msg
saveCapture appOnline capture =
    -- if appOnline then
    -- Http.post
    -- { url = "https://dwylapp.herokuapp.com/api/captures/create"
    --         , body = Http.jsonBody (captureEncode capture)
    --         , expect = Http.expectJson SaveCaptureResult captureDecoder
    --         }
    -- else
    -- if not online save the item in PouchDB via ports
    pouchDB capture


captureEncode : String -> JE.Value
captureEncode capture =
    JE.object [ ( "text", JE.string capture ) ]


captureDecoder : JD.Decoder String
captureDecoder =
    JD.field "text" JD.string
