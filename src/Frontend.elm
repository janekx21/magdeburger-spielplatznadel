port module Frontend exposing (..)

import Browser exposing (UrlRequest(..))
import Browser.Navigation as Nav
import Common exposing (..)
import Dict
import Element exposing (..)
import Element.Background as Background
import Element.Border as Border
import Element.Events
import Element.Font as Font
import Element.Input as Input
import Html
import Html.Attributes
import Html.Events
import Json.Decode as D
import Json.Encode as E
import Lamdera
import Material.Icons as Icons
import Material.Icons.Types exposing (Icon)
import Random
import Time
import Types exposing (..)
import UUID exposing (Seeds)
import Url
import Url.Parser as UP exposing ((</>), Parser, oneOf)


type alias Model =
    FrontendModel



--noinspection ElmUnusedSymbol


app =
    Lamdera.frontend
        { init = init
        , onUrlRequest = UrlClicked
        , onUrlChange = UrlChanged
        , update = update
        , updateFromBackend = updateFromBackend
        , subscriptions = subscriptions
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
      , currentGeoLocation = Nothing
      , modal = Nothing
      , seeds = UUID.Seeds (Random.initialSeed 1) (Random.initialSeed 2) (Random.initialSeed 3) (Random.initialSeed 4) -- TODO random generate seeds :>
      , playgrounds = []
      }
    , Lamdera.sendToBackend FetchPlaygrounds
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
        , UP.map AdminRoute (UP.s "admin")
        , UP.map PlaygroundAdminRoute (UP.s "admin" </> UP.s "playground" </> UP.string)
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
                    ( { model | route = parseUrl url }
                    , Lamdera.sendToBackend FetchPlaygrounds
                    )

                Just _ ->
                    -- any url change just closes the modal, the forward cancels out the back navigation
                    -- TODO what about url changes that do not come from back navigation
                    -- maybe do a route for modals?
                    ( { model | modal = Nothing }, Nav.forward model.key 1 )

        ReplaceUrl url ->
            ( model, Nav.replaceUrl model.key url )

        Online status ->
            ( { model | online = status }, Cmd.none )

        CloseModal ->
            ( { model | modal = Nothing }, Cmd.none )

        UpdatePlayground playground ->
            ( { model | playgrounds = model.playgrounds |> updateListItemViaId playground }, Lamdera.sendToBackend <| UploadPlayground playground )

        AddPlayground ->
            let
                ( playground, seeds ) =
                    initPlayground model.seeds
            in
            ( { model
                | playgrounds =
                    model.playgrounds
                        ++ [ playground ]
                , seeds = seeds
              }
            , Nav.pushUrl model.key <| "/admin/playground/" ++ playground.id
            )

        AddAward playground ->
            let
                ( award, seeds ) =
                    initAward model.seeds

                p2 =
                    { playground | awards = playground.awards |> updateListItemViaId award }
            in
            ( { model
                | playgrounds = model.playgrounds |> updateListItemViaId p2
                , seeds = seeds
              }
            , Cmd.none
            )

        OpenModal modal ->
            ( { model | modal = Just modal }, Cmd.none )

        CloseModalAnd frontendMsg ->
            case frontendMsg of
                CloseModalAnd _ ->
                    -- dont recurse pls
                    ( model, Cmd.none )

                _ ->
                    update frontendMsg (update CloseModal model |> Tuple.first)

        GeoLocationUpdated geoLocation ->
            ( { model | currentGeoLocation = geoLocation }, Cmd.none )



--RouteMsg routeMsg ->
--    case ( model.route, routeMsg ) of
--        ( PlaygroundAdminRoute routeModel, PlaygroundAdminRouteMsg localMsg ) ->
--            case localMsg of
--                MapClicked location ->
--                    let
--                        _ =
--                            Debug.log "clicked" location
--                    in
--                    ( model, Cmd.none )
--
--        ( _, _ ) ->
--            ( model, Cmd.none )


initPlayground : Seeds -> ( Playground, Seeds )
initPlayground s1 =
    let
        ( id, seeds ) =
            generateGuid s1
    in
    ( { id = id
      , awards = []
      , location = magdeburg
      , description = ""
      , title = ""
      , images = []
      , markerIcon = defaultMarkerIcon
      }
    , seeds
    )


updateFromBackend : ToFrontend -> Model -> ( Model, Cmd FrontendMsg )
updateFromBackend msg model =
    case msg of
        NoOpToFrontend ->
            ( model, Cmd.none )

        PlaygroundUploaded playground ->
            ( { model | playgrounds = model.playgrounds |> updateListItemViaId playground }, Cmd.none )

        PlaygroundsFetched playgrounds ->
            -- TODO do not replace unsaved playgrounds
            ( { model | playgrounds = model.playgrounds |> updateListViaId playgrounds }, Cmd.none )



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
                            Html.text <| "the playground " ++ guid ++ " does not exist"

                NewAwardRoute guid ->
                    let
                        award =
                            model |> allAwards |> List.filter (\a -> a.id == guid) |> List.head
                    in
                    case award of
                        Just a ->
                            viewNewAwardRoute model a

                        Nothing ->
                            Html.text <| "the award " ++ guid ++ " does not exist"

                AdminRoute ->
                    viewAdminRoute model

                PlaygroundAdminRoute guid ->
                    let
                        playground =
                            model.playgrounds |> List.filter (\p -> p.id == guid) |> List.head
                    in
                    case playground of
                        Just p ->
                            viewPlaygroundAdminRoute model p

                        Nothing ->
                            Html.text <| "the playground " ++ guid ++ " does not exist"

        body =
            case model.modal of
                Nothing ->
                    viewRoute model.route

                Just (ImageModal image) ->
                    viewImageModal image

                Just (AreYouSureModal label msg) ->
                    viewAreYouSureModal label msg
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


viewAreYouSureModal label msg =
    let
        button attr msg_ label_ =
            Input.button ([ Font.color black, padding 8, Border.rounded 8, width fill ] ++ attr) { onPress = Just msg_, label = el [ centerX ] <| text label_ }
    in
    layout
        [ width fill
        , height fill
        , Font.color white
        , Background.color black
        , Font.size 32
        , padding 32
        ]
    <|
        column [ centerX, centerY, spacing 16, width fill ]
            [ paragraph [ width fill ] [ text label ]
            , row [ width fill, spacing 8 ]
                [ button [ Background.color accent ] (CloseModalAnd msg) "Ja"
                , button [ Background.color primary ] CloseModal "Nein"
                ]
            ]


viewMainRoute : Model -> Html.Html FrontendMsg
viewMainRoute model =
    let
        playgrounds =
            case model.currentGeoLocation of
                Just geoLocation ->
                    model.playgrounds |> List.sortBy (\p -> locationDistanceInKilometers p.location geoLocation.location)

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
            , map (Maybe.map .location model.currentGeoLocation) (List.map playgroundMarker playgrounds)
            , column
                [ spacing 16, width fill ]
                (playgrounds |> List.map (playgroundItem (Maybe.map .location model.currentGeoLocation)))
            , column
                [ spacing 16, width fill ]
                [ el [ Font.bold ] <| text "debuggin menu"
                , link []
                    { url = "/admin"
                    , label =
                        el
                            [ padding 16
                            , Background.color secondaryDark
                            , Border.rounded 16
                            , Font.color white
                            ]
                        <|
                            text "Admin Seite"
                    }
                , column [ spacing 8, width fill ]
                    (allAwards model
                        |> List.map
                            (\{ id, title } ->
                                link [ width fill ]
                                    { url = "/new-award/" ++ id
                                    , label =
                                        el
                                            [ padding 16
                                            , Background.color secondaryDark
                                            , Border.rounded 16
                                            , Font.color white
                                            , width fill
                                            ]
                                        <|
                                            text <|
                                                "Stempel "
                                                    ++ title
                                                    ++ " eintragen"
                                    }
                            )
                    )
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
    in
    layout [ width fill, height fill, behindContent <| el [ height fill, width (px 24), padding 8 ] <| column [ centerX, height fill ] <| (List.repeat 12 dot |> List.intersperse bound) ] <|
        column [ width fill, height fill, spacing 32, padding 22, scrollbarY ]
            [ column [ spacing 24, width fill ]
                [ viewTitle "Stempelbuch"
                , viewParapraph "Hier findest du alle eingetragenen und austehenden Stempel."
                ]
            , viewAwardList <| allAwards model
            ]


allAwards model =
    model.playgrounds |> List.concatMap .awards


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


viewNewAwardRoute model award =
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
                            , moveDown 10
                            ]
                            { src = "/assets/images/stamp.svg"
                            , description = "a stamp"
                            }
                , below <|
                    column [ spacing 16, width fill ]
                        [ viewTitle "Glückwunsch!"
                        , viewParapraph <| "Du hast gerade den " ++ award.title ++ " Stempel gefunden. Trag ihn schnell in dein Stempelheft ein."
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
                [ el [ centerX, paddingXY 0 70, scale 1.7 ] <| viewAward 8 4 { award | found = Just <| Time.millisToPosix 0 }
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
            , mapCollapsed playground
            ]



-- TODO remove stuff like images, awards and playgrounds


viewAdminRoute : Model -> Html.Html FrontendMsg
viewAdminRoute model =
    let
        addPlaygroundButton =
            Input.button
                [ width fill
                , Border.rounded 16
                , Background.color secondary
                , width fill
                , height (px 64)
                , paddingXY 24 0
                , Font.color secondaryDark
                ]
                { onPress = Just AddPlayground
                , label = el [ centerX, centerY ] <| icon Icons.add
                }
    in
    layout
        [ width fill
        , height fill
        ]
    <|
        column [ width fill, height fill, spacing 32, padding 22, scrollbarY ]
            [ column [ spacing 24, width fill ]
                [ viewTitle "Admin Seite"
                , viewParapraph "Hier kannst du alles einstellen"
                ]
            , column
                [ spacing 16, width fill ]
                ((model.playgrounds |> List.map playgroundAdminItem) ++ [ addPlaygroundButton ])
            ]


viewPlaygroundAdminRoute : Model -> Playground -> Html.Html FrontendMsg
viewPlaygroundAdminRoute model playground =
    let
        adminGeneral =
            column [ spacing 32, width fill ]
                [ cuteInput "Titel des Spielplatzes" playground.title <| \v -> UpdatePlayground { playground | title = v }
                , cuteInputMultiline "Beschreibung des Spielpatzes" playground.description <| \v -> UpdatePlayground { playground | description = v }
                ]

        viewImagesAdmin : List Image -> Element FrontendMsg
        viewImagesAdmin images =
            column [ width fill, spacing 16 ]
                [ column [ width fill, spacing 16 ]
                    (images
                        |> List.indexedMap
                            (\index image_ ->
                                column
                                    [ Border.color secondary
                                    , Border.width 2
                                    , padding 16
                                    , Border.rounded 16
                                    , width fill
                                    , inFront <| cuteLabel "Bild"
                                    , spacing 16
                                    , inFront <| el [ moveUp 18, moveLeft 18 ] <| removeButton (UpdatePlayground { playground | images = removeInList images index })
                                    ]
                                    [ el [ centerX ] <| imagePreview image_
                                    , cuteInput "URL" image_.url <| \v -> UpdatePlayground { playground | images = replaceInList images index { image_ | url = v } }
                                    ]
                            )
                    )
                , addImageButton
                ]

        addImageButton =
            Input.button
                [ width fill
                , Border.rounded 16
                , Background.color secondary
                , width fill
                , height (px 64)
                , paddingXY 24 0
                , Font.color secondaryDark
                ]
                { onPress = Just <| UpdatePlayground { playground | images = playground.images ++ [ { url = "", description = "" } ] }
                , label = row [ centerX, centerY, spacing 8 ] [ icon Icons.add, icon Icons.image ]
                }

        viewAwardItemAdmin : Award -> Element FrontendMsg
        viewAwardItemAdmin award =
            column
                [ Border.color secondary
                , Border.width 2
                , padding 16
                , Border.rounded 16
                , width fill
                , inFront <| cuteLabel "Stempel"
                , spacing 16
                , inFront <| el [ moveUp 18, moveLeft 18 ] <| removeButton (UpdatePlayground { playground | awards = removeItemViaId award playground.awards })
                ]
                [ row [ width fill, spaceEvenly ]
                    [ viewAward 8 8 { award | found = Just <| Time.millisToPosix 0 }
                    , viewAward 8 8 { award | found = Nothing }
                    ]
                , cuteInput "Titel" award.title <| \v -> UpdatePlayground { playground | awards = playground.awards |> updateListItemViaId { award | title = v } }
                , cuteInput "Bild URL" award.image.url <| \v -> UpdatePlayground { playground | awards = playground.awards |> updateListItemViaId { award | image = { description = award.image.description, url = v } } }
                ]

        addAwardButton =
            Input.button
                [ width fill
                , Border.rounded 16
                , Background.color secondary
                , width fill
                , height (px 64)
                , paddingXY 24 0
                , Font.color secondaryDark
                ]
                { onPress = Just <| AddAward playground
                , label = row [ centerX, centerY, spacing 8 ] [ icon Icons.add, icon Icons.approval ]
                }

        adminMap =
            el
                [ width fill
                , aspect 7 4
                , flexBasisAuto
                , Border.rounded 16
                , style "overflow" "hidden"
                ]
            <|
                leafletMap
                    { camera = { location = playground.location, zoom = 14 }
                    , markers = [ playgroundMarker playground ]
                    , onClick = Just <| \v -> UpdatePlayground { playground | location = v }
                    }

        viewMarkerAdmin : MarkerIcon -> Element FrontendMsg
        viewMarkerAdmin marker =
            let
                real =
                    image [ inFront <| image [] { src = marker.url, description = "marker" } ] { src = marker.shadowUrl, description = "marker shadow" }
            in
            column [ Border.color secondary, Border.width 2, padding 16, Border.rounded 16, width fill, inFront <| cuteLabel "Markierung", spacing 16 ]
                [ row [ spaceEvenly, width fill ]
                    [ image [] { src = marker.url, description = "marker" }
                    , image [] { src = marker.shadowUrl, description = "marker shadow" }
                    , real
                    , el [ scale 0.8 ] <| real
                    , el [ scale 0.6 ] <| real
                    ]
                , cuteInput "URL" marker.url <| \v -> UpdatePlayground { playground | markerIcon = { marker | url = v } }
                , cuteInput "Schatten Url" marker.shadowUrl <| \v -> UpdatePlayground { playground | markerIcon = { marker | shadowUrl = v } }
                ]

        adminMapWithLocation =
            column [ spacing 16 ]
                [ let
                    location =
                        playground.location
                  in
                  row [ width fill, spacing 16 ]
                    [ cuteInput "Längengrad" (playground.location.lat |> String.fromFloat) <| \v -> UpdatePlayground { playground | location = { location | lat = String.toFloat v |> Maybe.withDefault location.lat } }
                    , cuteInput "Breitengrad" (playground.location.lng |> String.fromFloat) <| \v -> UpdatePlayground { playground | location = { location | lng = String.toFloat v |> Maybe.withDefault location.lng } }
                    ]
                , adminMap
                ]
    in
    layout [ width fill, height fill ] <|
        column [ width fill, height fill, spacing 64, padding 22, scrollbarY ]
            ([ el [ Font.color secondaryDark, centerX ] <| iconSized Icons.toys 64
             , adminGeneral
             , viewMarkerAdmin playground.markerIcon
             , viewImagesAdmin playground.images
             , column [ spacing 16, width fill ] <|
                (List.map viewAwardItemAdmin playground.awards ++ [ addAwardButton ])
             , adminMapWithLocation
             ]
                |> List.intersperse (el [ width fill, height (px 2), Background.color secondary ] <| none)
            )


removeButton msg =
    Input.button
        [ Font.color accent
        , Background.color white
        , Border.color secondary
        , Border.width 2
        , padding 4
        , Border.rounded 999
        ]
        { onPress = Just <| wrapInAreYouSure "Bist du dir sicher, dass du das wirklich löschen willst?" <| msg
        , label = icon Icons.delete
        }


replaceInList : List a -> Int -> a -> List a
replaceInList list index a =
    list
        |> List.indexedMap (\i x -> ( i, x ))
        |> Dict.fromList
        |> Dict.insert index a
        |> Dict.values


removeInList : List a -> Int -> List a
removeInList list index =
    list
        |> List.indexedMap (\i x -> ( i, x ))
        |> Dict.fromList
        |> Dict.remove index
        |> Dict.values


initAward : Seeds -> ( Award, Seeds )
initAward s1 =
    let
        ( id, s2 ) =
            generateGuid s1
    in
    ( { title = ""
      , id = id
      , image =
            { url = ""
            , description = ""
            }
      , found = Nothing
      }
    , s2
    )


playgroundMarker : Playground -> Marker
playgroundMarker playground =
    { location = playground.location
    , icon = playground.markerIcon
    , popupText = playground.title
    }


cuteInput label text_ msg =
    Input.text
        [ Border.width 0
        , Background.color secondary
        , paddingEach { top = 16, left = 10, right = 10, bottom = 12 }
        , Border.rounded 16
        , width fill
        , inFront <| cuteLabel label
        ]
        { text = text_
        , onChange = msg
        , placeholder = Nothing -- Just <| Input.placeholder [] none
        , label = Input.labelHidden label
        }


cuteLabel label =
    el [ Font.size 16, Background.color white, moveUp 10, centerX, paddingXY 6 2, Border.rounded 8 ] <| text label


cuteInputMultiline label text_ msg =
    Input.multiline
        [ Border.width 0
        , Background.color secondary
        , paddingEach { top = 16, left = 10, right = 10, bottom = 12 }
        , Border.rounded 16
        , width fill
        , inFront <| cuteLabel label
        ]
        { text = text_
        , onChange = msg
        , placeholder = Nothing -- Just <| Input.placeholder [] none
        , label = Input.labelHidden label
        , spellcheck = True
        }


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


wrapInAreYouSure label msg =
    OpenModal <| AreYouSureModal label <| msg


subscriptions _ =
    -- just for debugging :>
    --geoLocationUpdated <|
    --    \v ->
    --        let
    --            _ =
    --                Debug.log "elm location" v
    --
    --            _ =
    --                Debug.log "decoded location" (D.decodeString decodeGeoLocation v)
    --        in
    --        D.decodeString decodeGeoLocation v |> Result.toMaybe |> GeoLocationUpdated
    Sub.batch
        [ geoLocationUpdated <| (D.decodeString decodeGeoLocation >> Result.toMaybe >> GeoLocationUpdated)
        , geoLocationError <| \_ -> GeoLocationUpdated Nothing
        ]



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
    let
        button =
            Input.button
                [ Border.rounded 16
                , Background.color secondary
                , width (px 120)
                , height (px 120)
                , Background.image image.url
                ]
                { label = none, onPress = Just <| OpenModal <| ImageModal image }
    in
    el [ inFront <| displayIf (image.url /= "") button ] <| noImage


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
            , onClick = Nothing
            }


mapCollapsed playground =
    el
        [ width fill
        , aspect 7 4
        , flexBasisAuto
        , Border.rounded 16
        , style "overflow" "hidden"
        ]
    <|
        leafletMap { camera = { location = playground.location, zoom = 14 }, markers = [ playgroundMarker playground ], onClick = Nothing }


leafletMap : LeafletMapConfig -> Element FrontendMsg
leafletMap config =
    el [ behindContent <| el [ Background.image "/assets/images/map_background.jpg", width fill, height fill ] none, height fill, width fill ] <|
        html <|
            Html.node "leaflet-map"
                ([ Html.Attributes.attribute "data" (E.encode 0 (encodeLeafletMapConfig config))
                 , Html.Attributes.style "height" "100%"
                 , Html.Attributes.style "background" "transparent"
                 ]
                    ++ (case config.onClick of
                            Just onClick ->
                                [ Html.Events.on "click2" (D.map onClick (decodeDetail decodeLocation)) ]

                            Nothing ->
                                []
                       )
                )
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


playgroundAdminItem : Playground -> Element msg
playgroundAdminItem playground =
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
                ]
        , url = "/admin/playground/" ++ playground.id
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
                , style "mask" "url(\"/assets/images/dust_mask.png\") center / cover luminance"
                , inFront <| displayIf new newBatch
                ]
            <|
                emptyEl
                    [ Background.image award.image.url
                    , width fill
                    , height fill
                    , Border.rounded 9999
                    ]

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
        , inFront <| paragraph [ centerY, centerX, itim, Font.color secondary, padding 10, Font.center ] [ text award.title ]
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


encodeMarkers : List Marker -> E.Value
encodeMarkers markers =
    E.list encodeMarker markers


encodeMarker : Marker -> E.Value
encodeMarker marker =
    E.object
        [ ( "location", encodeLocation marker.location )
        , ( "icon", encodeMarkerIcon marker.icon )
        , ( "popupText", E.string marker.popupText )
        ]


encodeMarkerIcon : MarkerIcon -> E.Value
encodeMarkerIcon { url, shadowUrl } =
    E.object
        [ ( "url", E.string url )
        , ( "shadowUrl", E.string shadowUrl )
        ]


encodeLocation : Location -> E.Value
encodeLocation location =
    E.object
        [ ( "lat", E.float location.lat )
        , ( "lng", E.float location.lng )
        ]


decodeDetail : D.Decoder a -> D.Decoder a
decodeDetail a =
    D.field "detail" a


decodeLocation : D.Decoder Location
decodeLocation =
    D.map2 Location
        (D.field "lat" D.float)
        (D.field "lng" D.float)


decodeGeoLocation : D.Decoder GeoLocation
decodeGeoLocation =
    D.map2 GeoLocation
        (D.field "location" decodeLocation)
        (D.maybe <| D.field "heading" D.float)


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


generateGuid : UUID.Seeds -> ( Guid, UUID.Seeds )
generateGuid seeds =
    UUID.step seeds
        |> Tuple.mapFirst (UUID.toRepresentation UUID.Compact)



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


port geoLocationUpdated : (String -> msg) -> Sub msg


port geoLocationError : (String -> msg) -> Sub msg
