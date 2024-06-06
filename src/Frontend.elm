port module Frontend exposing (..)

import Browser exposing (UrlRequest(..))
import Browser.Navigation as Nav
import Element exposing (..)
import Element.Background as Background
import Element.Border as Border
import Element.Events
import Element.Font as Font
import Element.Input as Input
import Html
import Html.Attributes
import Json.Encode as E
import Lamdera
import Lamdera.Debug
import Material.Icons as Icons
import Material.Icons.Types exposing (Icon)
import Svg exposing (svg)
import Svg.Attributes
import Time
import Types exposing (..)
import Url
import Url.Parser as UP exposing ((</>), Parser, int, oneOf, s, string)


type alias Model =
    FrontendModel


app =
    Lamdera.frontend
        { init = init
        , onUrlRequest = UrlClicked
        , onUrlChange = UrlChanged
        , update = update
        , updateFromBackend = updateFromBackend
        , subscriptions = \m -> Sub.none
        , view = view
        }



-- Init


init : Url.Url -> Nav.Key -> ( FrontendModel, Cmd FrontendMsg )
init url key =
    let
        route =
            parseUrl url
    in
    ( { key = key
      , route = route
      , online = True
      , myLocation = Just { lat = 52.1, lng = 11.6 }
      , modal = Nothing
      , playgrounds =
            [ { title = "Spielplatz"
              , description = "Dinosaurier Spielplatz am Werder"
              , location = { lat = 52.13078, lng = 11.65262 }
              , id = "1234567"
              , images = []
              , awards =
                    [ { title = "Dino"
                      , id = "abc"
                      , found = Just <| Time.millisToPosix 0
                      , image =
                            { url = "https://www.trends.de/media/image/f3/6d/05/0258307-001.jpg"
                            , description = "Dino Stempel"
                            }
                      }
                    , { title = "Dino 2"
                      , id = "abcd"
                      , found = Nothing
                      , image =
                            { url = "https://www.trends.de/media/image/f3/6d/05/0258307-001.jpg"
                            , description = "Dino Stempel"
                            }
                      }
                    ]
              }
            , { title = "Spielplatz Schellheimer Platz"
              , description = "Der große Schelli Spielplatz in mitten von Stadtfeld ist mit vielen kleinen Spielsachen bestückt."
              , location = { lat = 52.126787, lng = 11.608743 }
              , id = "foobar"
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
              , id = "foobaroderso"
              , images =
                    [ { url = "https://www.magdeburg.de/media/custom/37_45203_1_r.JPG?1602064546"
                      , description = "Mittelstelle"
                      }
                    , { url = "https://bilder.spielplatztreff.de/spielplatzbild/spielplatz-schellheimerplatz-in-magdeburg_1410435124572.jpg"
                      , description = "Mittelstelle"
                      }
                    ]
              , awards =
                    [ { title = "Dino 3"
                      , id = "abcde"
                      , found = Nothing
                      , image =
                            { url = "https://www.trends.de/media/image/f3/6d/05/0258307-001.jpg"
                            , description = "Dino Stempel"
                            }
                      }
                    ]
              }
            ]
      }
    , Cmd.none
    )


magdeburg =
    { lat = 52.131667, lng = 11.639167 }


parseUrl url =
    UP.parse routeParser url |> Maybe.withDefault MainRoute


routeParser : Parser (Route -> a) a
routeParser =
    oneOf
        [ UP.map MainRoute UP.top
        , UP.map PlaygroundRoute (UP.s "playground" </> UP.string)
        , UP.map NewAwardRoute (UP.s "new-award" </> UP.string)
        , UP.map AwardsRoute (UP.s "award")
        ]



-- Update


update : FrontendMsg -> Model -> ( Model, Cmd FrontendMsg )
update msg model =
    case msg of
        NoOpFrontendMsg ->
            ( model, Cmd.none )

        UrlClicked urlRequest ->
            case urlRequest of
                Internal url ->
                    ( model
                    , Nav.pushUrl model.key (Url.toString url)
                    )

                External url ->
                    ( model
                    , Nav.load url
                    )

        UrlChanged url ->
            case model.modal of
                Nothing ->
                    ( { model | route = parseUrl url }, Cmd.none )

                Just _ ->
                    -- any url change just closes the modal, the forward cancels out the back navigation
                    -- TODO what about url changes that do not come from back navigation
                    -- maybe do a route for modals?
                    ( { model | modal = Nothing }, Nav.forward model.key 1 )

        ReplaceUrl url ->
            ( model, Nav.replaceUrl model.key url )

        Online status ->
            ( { model | online = status }, Cmd.none )

        OpenImageModal image ->
            ( { model | modal = Just <| ImageModal image }, Cmd.none )

        CloseModal ->
            ( { model | modal = Nothing }, Cmd.none )


updateFromBackend : ToFrontend -> Model -> ( Model, Cmd FrontendMsg )
updateFromBackend msg model =
    case msg of
        NoOpToFrontend ->
            ( model, Cmd.none )



-- View


view : Model -> Browser.Document FrontendMsg
view model =
    let
        viewRoute route =
            case route of
                MainRoute ->
                    viewMainRoute model

                AwardsRoute ->
                    viewAwardsRoute model

                PlaygroundRoute guid ->
                    let
                        playground =
                            model.playgrounds |> List.filter (\p -> p.id == guid) |> List.head
                    in
                    case playground of
                        Just p ->
                            viewPlaygroundRoute model p

                        Nothing ->
                            Html.text "404 :<"

                NewAwardRoute guid ->
                    viewNewAwardRoute model

                AdminRoute ->
                    Html.text "todo"

        body =
            case model.modal of
                Nothing ->
                    viewRoute model.route

                Just (ImageModal image) ->
                    viewImageModal image
    in
    { title = "", body = [ body ] }


viewImageModal i =
    let
        close =
            Input.button [] <|
                { label = iconSized Icons.close 48
                , onPress = Just <| CloseModal
                }

        imageLink =
            link [] <|
                { label = iconSized Icons.image 48
                , url = i.url
                }

        closingTrigger =
            el
                [ height fill
                , width fill
                , Element.Events.onClick <| CloseModal
                ]
            <|
                none
    in
    layout
        [ width fill
        , height fill
        , inFront <|
            el [ alignBottom, alignRight, padding 32 ] <|
                lifted <|
                    row [ spacing 8 ]
                        [ imageLink, close ]
        , Background.image "/assets/images/map_background.jpg"
        ]
    <|
        column [ height fill, width fill, padding 8 ]
            [ closingTrigger
            , image
                [ width fill
                , centerY
                , Border.rounded 16
                , style "overflow" "hidden"
                , Element.Events.onClick <| NoOpFrontendMsg
                ]
                { src = i.url, description = i.description }
            , closingTrigger
            ]


viewMainRoute : Model -> Html.Html msg
viewMainRoute model =
    let
        playgrounds =
            case model.myLocation of
                Just loc ->
                    model.playgrounds |> List.sortBy (\p -> locationDistanceInKilometers p.location loc)

                Nothing ->
                    model.playgrounds
    in
    layout
        [ width fill
        , height fill
        , inFront <|
            el [ alignBottom, alignRight, padding 32 ] <|
                buttonAwards
        ]
    <|
        column [ width fill, height fill, spacing 32, padding 22, scrollbarY ]
            [ column [ spacing 24, width fill ]
                [ viewTitle "Magdeburger Spielplatznadel"
                , viewParapraph "Fangt jetzt an Stempel zu sammeln und schaut wie viel ihr bekommen könnt."
                ]
            , map model.myLocation (List.map .location playgrounds)
            , column
                [ spacing 16, width fill ]
                (playgrounds |> List.map (playgroundItem model.myLocation))
            , column
                [ spacing 16, width fill ]
                [ el [ Font.bold ] <| text "debuggin menu"
                , link []
                    { url = "/new-award/placeholder"
                    , label =
                        el
                            [ padding 16
                            , Background.color secondaryDark
                            , Border.rounded 16
                            , Font.color white
                            ]
                        <|
                            text "Neuer Stempel"
                    }
                ]
            ]


viewAwardsRoute model =
    let
        bound =
            el [ paddingXY 0 2, centerX, height fill ] <|
                el [ width (px 6), height fill, Background.color secondary, Border.rounded 999 ] <|
                    none

        dot =
            el [ width (px 12), height (px 12), Background.color secondaryDark, Border.rounded 999 ] <| none

        allAwards =
            model.playgrounds |> List.concatMap .awards
    in
    layout [ width fill, height fill, behindContent <| el [ height fill, width (px 24), padding 8 ] <| column [ centerX, height fill ] <| (List.repeat 12 dot |> List.intersperse bound) ] <|
        column [ width fill, height fill, spacing 32, padding 22, scrollbarY ]
            [ column [ spacing 24, width fill ]
                [ viewTitle "Stempelbuch"
                , viewParapraph "Hier findest du alle eingetragenen und austehenden Stempel."
                ]
            , viewAwardList allAwards
            ]


viewAwardList awards =
    let
        ( offX, offY ) =
            ( 12, 12 )
    in
    if List.isEmpty awards then
        row [ Font.color secondaryDark, spacing 8 ] [ text "Hier gibt es keine Stempel", icon Icons.sentiment_dissatisfied ]

    else
        row
            [ width fill, style "flex-wrap" "wrap", style "gap" "32px", justifyCenter ]
        <|
            List.map (viewAward offX offY) awards


viewNewAwardRoute model =
    layout [ width fill, height fill ] <|
        column [ width fill, height fill, spacing 32, padding 22, scrollbarY ]
            [ column
                [ spacing 16
                , width fill
                , centerY
                , above <|
                    el
                        [ width fill
                        ]
                    <|
                        image
                            [ width fill
                            , moveDown 45
                            ]
                            { src = "/assets/images/stamp.svg"
                            , description = "a stamp"
                            }
                , below <|
                    column [ spacing 16, width fill ]
                        [ placeholderLarger
                        , linePlaceholder 18
                        , linePlaceholder 4
                        , replacingLink [ centerX, padding 16 ]
                            { url = "/award"
                            , label =
                                el
                                    [ padding 16
                                    , Background.color secondaryDark
                                    , Border.rounded 16
                                    , Font.color white
                                    , Font.size 32
                                    ]
                                <|
                                    text "Eintragen"
                            }
                        ]
                ]
                [ el [ centerX, paddingXY 0 100, scale 1.7 ] <| awardPlaceholder True 8 4 True
                ]
            ]


viewPlaygroundRoute : Model -> Playground -> Html.Html FrontendMsg
viewPlaygroundRoute model playground =
    layout [ width fill, height fill ] <|
        column [ width fill, height fill, spacing 32, padding 22, scrollbarY ]
            [ el [ Font.color secondaryDark, centerX ] <| iconSized Icons.toys 64
            , column [ spacing 32, width fill ]
                [ viewTitle playground.title
                , viewParapraph playground.description
                ]
            , viewImageStrip playground.images
            , column [ spacing 16, width fill ] [ viewAwardList playground.awards ]
            , mapCollapsed playground.location
            ]


viewTitle label =
    paragraph [ spacing 16 ]
        [ el [ Font.bold, Font.size 32, Font.color secondaryDark ] <| text label
        ]


viewParapraph label =
    paragraph [ spacing 8, Font.color secondaryDark ] [ text label ]


viewImageStrip images =
    case images of
        [] ->
            none

        _ ->
            row [ scrollbarX, height (px 140), spacing 16, width fill, style "flex" "none" ] <|
                List.map imagePreview images



-- Elements


linePlaceholder space =
    row [ width fill ]
        [ placeholder
        , el [ width (px (space * 8)) ] <| none
        ]


placeholder =
    el [ Border.rounded 16, Background.color secondary, width fill, height (px 36) ] <| none


placeholderLarger =
    el [ Border.rounded 16, Background.color secondaryDark, width fill, height (px 48) ] <| none


placeholderImage =
    el [ Border.rounded 16, Background.color secondary, width (px 120), height (px 120) ] <| el [ centerX, centerY, Font.color secondaryDark ] <| icon Icons.image


noImage =
    el [ Border.rounded 16, Background.color secondary, width (px 120), height (px 120) ] <| el [ centerX, centerY, Font.color secondaryDark ] <| icon Icons.image_not_supported


imagePreview image =
    Input.button
        [ Border.rounded 16
        , Background.color secondary
        , width (px 120)
        , height (px 120)
        , Background.image image.url
        ]
        { label = none, onPress = Just <| OpenImageModal image }


mapPlaceholder =
    el
        [ Border.rounded 16
        , Background.color secondary
        , width fill
        , square
        , flexBasisAuto
        ]
    <|
        el [ centerX, centerY, itim, Font.color secondaryDark ] <|
            text "map"


map location marker =
    el
        [ width fill
        , square
        , flexBasisAuto
        , Border.rounded 16
        , style "overflow" "hidden"
        ]
    <|
        leafletMap
            { camera =
                { location = location |> Maybe.withDefault magdeburg
                , zoom = 12
                }
            , markers = marker
            }


mapCollapsed location =
    el
        [ width fill
        , aspect 7 4
        , flexBasisAuto
        , Border.rounded 16
        , style "overflow" "hidden"
        ]
    <|
        leafletMap { camera = { location = location, zoom = 14 }, markers = [ location ] }


leafletMap : LeafletMapConfig -> Element msg
leafletMap config =
    el [ behindContent <| el [ Background.image "/assets/images/map_background.jpg", width fill, height fill ] none, height fill, width fill ] <|
        html <|
            Html.node "leaflet-map"
                [ Html.Attributes.attribute "data" (E.encode 0 (encodeLeafletMapConfig config))
                , Html.Attributes.style "height" "100%"
                , Html.Attributes.style "background" "transparent"
                ]
                []


playgroundItemPlaceholder km =
    link
        [ Border.rounded 16
        , Background.color secondary
        , width fill
        , height (px 64)
        , paddingXY 24 0
        ]
    <|
        { label =
            row [ centerY, width fill, Font.color secondaryDark ]
                [ icon Icons.local_play
                , el [ alignRight, itim, Font.size 24 ] <|
                    text <|
                        (String.fromFloat km ++ "km")
                ]
        , url = "/playground/placeholder"
        }


playgroundItem : Maybe Location -> Playground -> Element msg
playgroundItem location playground =
    let
        viewDistance loc =
            let
                km =
                    locationDistanceInKilometers loc playground.location

                kmString =
                    toFloat (round (km * 100)) / 100 |> String.fromFloat
            in
            el [ alignRight, itim, Font.size 24 ] <|
                text <|
                    (kmString ++ "km")
    in
    link
        [ Border.rounded 16
        , Background.color secondary
        , width fill
        , height (px 64)
        , paddingXY 24 0
        ]
    <|
        { label =
            row [ centerY, width fill, Font.color secondaryDark, spacing 8 ]
                [ icon Icons.toys
                , textTruncated playground.title
                , location |> Maybe.map viewDistance |> Maybe.withDefault none
                ]
        , url = "/playground/" ++ playground.id
        }


awardPlaceholder got offX offY new =
    el
        [ Border.rounded 999
        , width <| px 130
        , height <| px 130
        , Border.color secondary
        , Border.width 8
        , Border.dashed
        , inFront <|
            if got then
                el
                    [ width fill
                    , height fill
                    , Border.color secondaryDark
                    , Border.width 8
                    , Border.rounded 999
                    , Background.color secondary
                    , moveRight offX
                    , moveDown offY
                    , scale 1.1
                    , inFront <|
                        if new then
                            el
                                [ alignRight
                                , alignBottom
                                , Background.color white
                                , Font.color secondaryDark
                                , paddingXY 12 8
                                , Border.rounded 999
                                , Border.color accent
                                , Border.width 8
                                , moveRight 16
                                , moveDown 16
                                , rotate -0.3
                                ]
                            <|
                                text "neu!"

                        else
                            none
                    ]
                <|
                    el
                        [ centerX
                        , centerY
                        , Font.color secondaryDark
                        ]
                    <|
                        iconSized Icons.stars 64

            else
                none
        ]
    <|
        none


viewAward : Float -> Float -> Award -> Element msg
viewAward offX offY award =
    let
        new =
            False

        got =
            not <| award.found == Nothing

        awardEl =
            el
                [ width fill
                , height fill
                , Border.color secondaryDark
                , Border.width 8
                , Border.rounded 999
                , Background.color secondary
                , moveRight offX
                , moveDown offY
                , scale 1.1
                , inFront <| displayIf new newBatch
                ]
            <|
                emptyEl [ Background.image award.image.url, width fill, height fill, Border.rounded 9999 ]

        newBatch =
            el
                [ alignRight
                , alignBottom
                , Background.color white
                , Font.color secondaryDark
                , paddingXY 12 8
                , Border.rounded 999
                , Border.color accent
                , Border.width 8
                , moveRight 16
                , moveDown 16
                , rotate -0.3
                ]
            <|
                text "neu!"
    in
    emptyEl
        [ Border.rounded 999
        , width <| px 130
        , height <| px 130
        , Border.color secondary
        , Border.width 8
        , Border.dashed
        , inFront <| el [ centerY, centerX, itim, Font.color secondary ] <| text award.title
        , inFront <| displayIf got awardEl
        ]


buttonAwards =
    link
        [ Background.color secondaryDark
        , Border.rounded 999
        , padding 16
        , Font.color white
        , Border.shadow { offset = ( 0, 4 ), size = 0, blur = 18, color = rgba 0 0 0 0.25 }
        ]
    <|
        { label =
            iconSized Icons.approval 48
        , url = "/award"
        }


lifted child =
    el
        [ Background.color secondaryDark
        , Border.rounded 999
        , padding 16
        , Font.color white
        , Border.shadow { offset = ( 0, 4 ), size = 0, blur = 18, color = rgba 0 0 0 0.25 }
        ]
        child


closeButton =
    Input.button
        [ Background.color secondaryDark
        , Border.rounded 999
        , padding 16
        , Font.color white
        , Border.shadow { offset = ( 0, 4 ), size = 0, blur = 18, color = rgba 0 0 0 0.25 }
        ]
    <|
        { label =
            iconSized Icons.close 48
        , onPress = Just <| CloseModal
        }


icon : Icon msg -> Element msg
icon icon_ =
    iconSized icon_ 24


iconSized : Icon msg -> Int -> Element msg
iconSized icon_ size =
    el [] <| html <| icon_ size Material.Icons.Types.Inherit


replacingLink attr { url, label } =
    Input.button attr { onPress = Just <| ReplaceUrl url, label = label }


emptyEl attr =
    el attr <| none


displayIf boolean element =
    if boolean then
        element

    else
        none



-- Utility


encodeLeafletMapConfig : LeafletMapConfig -> E.Value
encodeLeafletMapConfig value =
    E.object
        [ ( "camera", encodeCamera value.camera )
        , ( "markers", encodeMarkers value.markers )
        ]


encodeCamera : Camera -> E.Value
encodeCamera value =
    E.object
        [ ( "zoom", E.int value.zoom )
        , ( "location", encodeLocation value.location )
        ]


encodeMarkers : List Location -> E.Value
encodeMarkers locations =
    E.list encodeLocation locations


encodeLocation : Location -> E.Value
encodeLocation location =
    E.object
        [ ( "lat", E.float location.lat )
        , ( "lng", E.float location.lng )
        ]


square =
    aspect 1 1


textTruncated label =
    el
        [ style "white-space" "nowrap"
        , style "overflow" "hidden"
        , style "text-overflow" "ellipsis"
        , style "flex-grow" "9999"
        ]
    <|
        text label


aspect a b =
    style "aspect-ratio" (String.fromInt a ++ "/" ++ String.fromInt b)


flexBasisAuto =
    style "flex-basis" "auto"


justifyCenter =
    style "justify-content" "center"


itim =
    Font.family [ Font.typeface "Itim" ]


style key value =
    htmlAttribute <| Html.Attributes.style key value


earthRadiusInKilometers : Float
earthRadiusInKilometers =
    6371.0


{-| Calculate the Haversine distance between two locations
-}
locationDistanceInKilometers : Location -> Location -> Float
locationDistanceInKilometers loc1 loc2 =
    let
        lat1 =
            degrees loc1.lat

        lng1 =
            degrees loc1.lng

        lat2 =
            degrees loc2.lat

        lng2 =
            degrees loc2.lng

        dLat =
            lat2 - lat1

        dLng =
            lng2 - lng1

        -- Haversine Formula
        a =
            sin (dLat / 2)
                ^ 2
                + cos lat1
                * cos lat2
                * sin (dLng / 2)
                ^ 2

        c =
            2 * atan2 (sqrt a) (sqrt (1 - a))
    in
    earthRadiusInKilometers * c



-- 4.96km
-- Theme
-- gray ligth
--    rgb255 224 231 236
-- gray drak
--    rgb255 148 162 171
-- green
--    rgb255 151 214 115


primary =
    rgb255 151 214 115


secondary =
    rgb255 244 215 190


secondaryDark =
    rgb255 233 124 30


accent =
    rgb 0.96 0.3 0.4


black =
    rgb 0 0 0


white =
    rgb 1 1 1



-- Lab


saveCapture : Bool -> String -> Cmd FrontendMsg
saveCapture appOnline capture =
    pouchDB capture


port online : (Bool -> msg) -> Sub msg


port pouchDB : String -> Cmd msg
