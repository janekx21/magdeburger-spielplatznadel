port module Frontend exposing (..)

import Browser exposing (UrlRequest(..))
import Browser.Navigation as Nav
import Element exposing (..)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Html
import Html.Attributes
import Html.Keyed
import Lamdera
import Material.Icons as Icons
import Material.Icons.Types exposing (Icon)
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
    ( FrontendModel key route "" "" True
    , Cmd.none
    )


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
            ( { model | route = parseUrl url }, Cmd.none )

        NoOpFrontendMsg ->
            ( model, Cmd.none )

        Capture text ->
            ( { model | capture = text }, Cmd.none )

        CreateCapture ->
            ( model, saveCapture model.online model.capture )

        Online status ->
            ( { model | online = status }, Cmd.none )

        ReplaceUrl url ->
            ( model, Nav.replaceUrl model.key url )


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
                    viewPlaygroundRoute model

                NewAwardRoute guid ->
                    viewNewAwardRoute model
    in
    { title = ""
    , body =
        [ Html.node "link" [ Html.Attributes.rel "stylesheet", Html.Attributes.href "https://fonts.googleapis.com/css?family=Itim" ] []
        , viewRoute model.route

        -- , Html.Lazy.lazy <|
        --     Html.div
        --         [ Html.Attributes.style "position" "absolute"
        --         , Html.Attributes.style "height" "100%"
        --         , Html.Attributes.style "width" "100%"
        --         , Html.Attributes.class "old-view"
        --         ]
        --         [ case model.oldRoute of
        --             Nothing ->
        --                 Html.div [] []
        --             Just route ->
        --                 viewRoute route
        --         ]
        -- , Html.Lazy.lazy <|
        --     Html.div
        --         [ Html.Attributes.style "height" "100%"
        --         , Html.Attributes.style "width" "100%"
        --         , Html.Attributes.style "position" "absolute"
        --         , Html.Attributes.class "new-view"
        --         ]
        --         [ viewRoute model.route
        --         ]
        ]
    }


viewMainRoute model =
    layout
        [ width fill
        , height fill
        , inFront <|
            el [ alignBottom, alignRight, padding 32 ] <|
                buttonAwards
        ]
    <|
        column [ width fill, height fill, spacing 32, padding 22, scrollbarY ]
            [ column [ spacing 16, width fill ]
                [ placeholderLarger
                , linePlaceholder 8
                , linePlaceholder 4
                ]
            , map
            , column
                [ spacing 16, width fill ]
                [ playgroundItemPlaceholder 3
                , playgroundItemPlaceholder 4.2
                , playgroundItemPlaceholder 4.5
                , playgroundItemPlaceholder 7.2
                , playgroundItemPlaceholder 7.9
                , playgroundItemPlaceholder 12
                ]
            , column
                [ spacing 16, width fill ]
                [ el [ Font.bold ] <| text "debuggin menu"
                , link []
                    { url = "/new-award/placeholder"
                    , label =
                        el
                            [ padding 16
                            , Background.color grayDark
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
                el [ width (px 6), height fill, Background.color grayLight, Border.rounded 999 ] <|
                    none

        dot =
            el [ width (px 12), height (px 12), Background.color grayDark, Border.rounded 999 ] <| none
    in
    layout [ width fill, height fill, behindContent <| el [ height fill, width (px 24), padding 8 ] <| column [ centerX, height fill ] <| (List.repeat 12 dot |> List.intersperse bound) ] <|
        column [ width fill, height fill, spacing 32, padding 22, scrollbarY ]
            [ column [ spacing 16, width fill ]
                [ placeholderLarger
                , linePlaceholder 18
                ]
            , row
                [ width fill, style "flex-wrap" "wrap", style "gap" "32px", justifyCenter ]
                [ awardPlaceholder True 3 -9 True
                , awardPlaceholder False 12 -4 False
                , awardPlaceholder True -1 16 False
                , awardPlaceholder True -8 1 False
                , awardPlaceholder False 7 9 False
                , awardPlaceholder True -8 4 False
                , awardPlaceholder True -5 9 False
                , awardPlaceholder False 1 -4 False
                , awardPlaceholder True 12 -16 False
                , awardPlaceholder True -3 12 False
                , awardPlaceholder False -7 2 False
                ]
            ]


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
                                    , Background.color grayDark
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


viewPlaygroundRoute model =
    layout [ width fill, height fill ] <|
        column [ width fill, height fill, spacing 32, padding 22, scrollbarY ]
            [ el [ Font.color grayDark, centerX ] <| iconSized Icons.toys 64
            , column [ spacing 16, width fill ]
                [ placeholderLarger
                , linePlaceholder 8
                , linePlaceholder 3
                , linePlaceholder 7
                , linePlaceholder 2
                , linePlaceholder 4
                , linePlaceholder 20
                ]
            , row [ scrollbarX, height (px 140), spacing 16, width fill, style "flex" "none" ]
                [ placeholderImage
                , placeholderImage
                , placeholderImage
                , placeholderImage
                , placeholderImage
                , placeholderImage
                ]
            , mapCollapsed
            ]



-- Elements


linePlaceholder space =
    row [ width fill ]
        [ placeholder
        , el [ width (px (space * 8)) ] <| none
        ]


placeholder =
    el [ Border.rounded 16, Background.color grayLight, width fill, height (px 36) ] <| none


placeholderLarger =
    el [ Border.rounded 16, Background.color grayDark, width fill, height (px 48) ] <| none


placeholderImage =
    el [ Border.rounded 16, Background.color grayLight, width (px 120), height (px 120) ] <| el [ centerX, centerY, Font.color grayDark ] <| icon Icons.image


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


map =
    el
        [ width fill
        , square
        , flexBasisAuto
        , Border.rounded 16
        , style "overflow" "hidden"
        ]
    <|
        html <|
            Html.node "my-custom-element"
                [ Html.Attributes.attribute "lat-lng" "52.131667,11.639167"
                ]
                []


mapCollapsed =
    el
        [ width fill
        , aspect 7 4
        , flexBasisAuto
        , Border.rounded 16
        , style "overflow" "hidden"
        ]
    <|
        html <|
            Html.node "my-custom-element" [] []


playgroundItemPlaceholder km =
    link
        [ Border.rounded 16
        , Background.color grayLight
        , width fill
        , height (px 64)
        , paddingXY 24 0
        ]
    <|
        { label =
            row [ centerY, width fill, Font.color grayDark ]
                [ icon Icons.local_play
                , el [ alignRight, itim, Font.size 24 ] <|
                    text <|
                        (String.fromFloat km ++ "km")
                ]
        , url = "/playground/placeholder"
        }


awardPlaceholder got offX offY new =
    el
        [ Border.rounded 999
        , width <| px 130
        , height <| px 130
        , Border.color grayLight
        , Border.width 8
        , Border.dashed
        , inFront <|
            if got then
                el
                    [ width fill
                    , height fill
                    , Border.color grayDark
                    , Border.width 8
                    , Border.rounded 999
                    , Background.color grayLight
                    , moveRight offX
                    , moveDown offY
                    , scale 1.1
                    , inFront <|
                        if new then
                            el
                                [ alignRight
                                , alignBottom
                                , Background.color white
                                , Font.color grayDark
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
                        , Font.color grayDark
                        ]
                    <|
                        iconSized Icons.stars 64

            else
                none
        ]
    <|
        none


buttonAwards =
    link
        [ Background.color grayDark
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


icon : Icon msg -> Element msg
icon icon_ =
    iconSized icon_ 24


iconSized : Icon msg -> Int -> Element msg
iconSized icon_ size =
    el [] <| html <| icon_ size Material.Icons.Types.Inherit


replacingLink attr { url, label } =
    Input.button attr { onPress = Just <| ReplaceUrl url, label = label }



-- Utility


square =
    aspect 1 1


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



-- Theme


grayLight =
    rgb255 224 231 236


grayDark =
    rgb255 148 162 171


white =
    rgb 1 1 1


accent =
    rgb 0.96 0.3 0.4



-- Lab


saveCapture : Bool -> String -> Cmd FrontendMsg
saveCapture appOnline capture =
    pouchDB capture


port online : (Bool -> msg) -> Sub msg


port pouchDB : String -> Cmd msg
