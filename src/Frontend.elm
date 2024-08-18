port module Frontend exposing (app)

import Animator
import Animator.Css
import Browser exposing (UrlRequest(..))
import Browser.Navigation as Nav
import Common exposing (..)
import Element exposing (..)
import Element.Background as Background
import Element.Border as Border
import Element.Events
import Element.Font as Font
import Element.Input as Input
import File
import File.Select as Select
import Html
import Html.Attributes
import Html.Events
import Http
import IdSet
import Image
import Json.Decode as D
import Json.Encode as E
import Lamdera
import Material.Icons as Icons
import Material.Icons.Types exposing (Icon)
import QRCode
import Random
import Task
import Types exposing (..)
import UUID exposing (Seeds)
import Url
import Url.Parser as UP exposing ((</>), Parser, oneOf)



-- TODO Url.Builder


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

        seed =
            Random.independentSeed
    in
    ( { key = key
      , route = Animator.init route
      , online = True
      , currentGeoLocation = Nothing
      , modal = Nothing

      -- the seeds are just a placeholder that will be overriten as soon as possible
      , seeds = UUID.Seeds (Random.initialSeed 1) (Random.initialSeed 2) (Random.initialSeed 3) (Random.initialSeed 4)
      , playgrounds = IdSet.empty
      , user = Nothing
      }
    , Random.generate SetSeed (Random.map4 UUID.Seeds seed seed seed seed)
    )



-- Update


update : FrontendMsg -> Model -> ( Model, Cmd FrontendMsg )
update msg model =
    case msg of
        NoOpFrontendMsg ->
            ( model, Cmd.none )

        UrlClicked urlRequest ->
            case urlRequest of
                Internal url ->
                    ( newRoute url model
                      -- ( model
                    , Nav.pushUrl model.key (Url.toString url)
                    )

                External url ->
                    ( model
                    , Nav.load url
                    )

        UrlChanged url ->
            case model.modal of
                Nothing ->
                    let
                        route =
                            parseUrl url
                    in
                    let
                        collectCmd =
                            case route of
                                NewAwardRoute guid ->
                                    Lamdera.sendToBackend <| Collect guid

                                _ ->
                                    Cmd.none
                    in
                    ( newRoute url model
                    , collectCmd
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
            ( { model | playgrounds = model.playgrounds |> IdSet.insert playground }, Lamdera.sendToBackend <| UploadPlayground playground )

        AddPlayground ->
            let
                ( playground, seeds ) =
                    initPlayground model.seeds
            in
            ( { model
                | playgrounds = model.playgrounds |> IdSet.insert playground
                , seeds = seeds
              }
            , Nav.pushUrl model.key <| "/admin/playground/" ++ playground.id
            )

        RemovePlaygroundLocal playground ->
            ( { model | playgrounds = IdSet.remove playground.id model.playgrounds }, Cmd.batch [ Nav.back model.key 1, Lamdera.sendToBackend <| RemovePlayground playground ] )

        AddAward playground ->
            let
                ( award, seeds ) =
                    initAward model.seeds

                p2 =
                    { playground | awards = playground.awards |> updateListItemViaId award }
            in
            ( { model
                | playgrounds = model.playgrounds |> IdSet.insert p2
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

        StorageLoaded data ->
            let
                ( userId, seeds ) =
                    case data of
                        Just id ->
                            ( id, model.seeds )

                        Nothing ->
                            IdSet.generateId model.seeds
            in
            ( { model | user = Just { id = userId, awards = IdSet.empty }, seeds = seeds }, Cmd.batch [ saveStorage userId, Lamdera.sendToBackend <| SetConnectedUser userId ] )

        LoginWithId userId ->
            ( { model | user = Just { id = userId, awards = IdSet.empty } }
            , Cmd.batch [ Nav.replaceUrl model.key "/", Lamdera.sendToBackend <| SetConnectedUser userId, saveStorage userId ]
            )

        SetSeed seeds ->
            ( { model | seeds = seeds }, Cmd.none )

        Share data ->
            ( model, share data )

        ImageRequested target ->
            ( model, Select.file [ "image/*" ] (ImageSelected target) )

        ImageSelected target file ->
            -- ( model, Lamdera.sendToBackend <| UploadImage file )
            ( model
            , File.toUrl file
                |> Task.perform (ImageLoaded target)
            )

        ImageLoaded target dataUrl ->
            -- ( model, Lamdera.sendToBackend <| UploadImage bytes )
            ( model, imageUploadCmd dataUrl )

        ImageUploaded result ->
            -- let
            --     _ =
            --         Debug.log "image upload result" result
            -- in
            ( model, Cmd.none )

        Tick newTime ->
            ( Animator.update newTime animator model, Cmd.none )


newRoute : Url.Url -> Model -> Model
newRoute url model =
    { model
        | route =
            model.route
                |> Animator.go (Animator.millis 500) (parseUrl url)
    }


imageUploadCmd dataUrl =
    Http.post
        { url = "https://api.imgur.com/3/image"
        , expect = Http.expectString ImageUploaded
        , body =
            Http.jsonBody <|
                E.object
                    [ ( "image", E.string dataUrl )
                    ]

        -- Http.multipartBody
        --     [ Http.stringPart "type" "base64"
        --     , Http.stringPart "title" "some title"
        --     , Http.stringPart "description" "some description"
        --     , Http.stringPart "image" dataUrl
        --     ]
        }



-- case target of
--     PlaygroundImageTarget playground ->
--         update
--             (UpdatePlayground { playground | images = playground.images ++ [ { url = dataUrl, description = "" } ] })
--             model


initPlayground : Seeds -> ( Playground, Seeds )
initPlayground s1 =
    IdSet.assignId
        ( { id = IdSet.nilId
          , awards = []
          , location = magdeburg
          , description = ""
          , title = ""
          , images = []
          , markerIcon = defaultMarkerIcon
          }
        , s1
        )


updateFromBackend : ToFrontend -> Model -> ( Model, Cmd FrontendMsg )
updateFromBackend msg model =
    case msg of
        NoOpToFrontend ->
            ( model, Cmd.none )

        PlaygroundUploaded playground ->
            ( { model | playgrounds = model.playgrounds |> IdSet.insert playground }, Cmd.none )

        PlaygroundRemoved playground ->
            ( { model | playgrounds = model.playgrounds |> IdSet.remove playground.id }, Cmd.none )

        PlaygroundsFetched playgrounds ->
            ( { model | playgrounds = model.playgrounds |> IdSet.union (IdSet.fromList playgrounds) }, Cmd.none )

        UserUpdated user ->
            ( { model | user = Just user }, Cmd.none )



-- View


view : Model -> Browser.Document FrontendMsg
view model =
    { title = ""
    , body =
        -- The flex box will enlarge from the flex-basis. This needs to be disabled on scolling content
        [ Html.node "style" [] [ Html.text ".s.sby {flex-basis: 0 !important;}" ]
        , Html.div
            [ Html.Attributes.style "height" "100%"
            , Html.Attributes.style "width" "100%"
            , Html.Attributes.style "position" "relative"
            ]
            [ layout [] <| none
            , Animator.Css.div model.route
                [ Animator.Css.transform <|
                    \state ->
                        if Animator.upcoming state model.route then
                            Animator.Css.xy { x = 0, y = 0 }

                        else
                            Animator.Css.xy { x = 460 * 2, y = 0 }
                , Animator.Css.opacity <|
                    \state ->
                        (if Animator.upcoming state model.route then
                            Animator.at 1

                         else
                            Animator.at 0
                        )
                            |> Animator.leaveSmoothly 0
                            |> Animator.arriveSmoothly 1
                ]
                [ Html.Attributes.style "inset" "0"
                , Html.Attributes.style "position" "absolute"
                ]
                [ viewRoute (Animator.current model.route) model
                ]
            , Animator.Css.div model.route
                [ Animator.Css.transform <|
                    \state ->
                        if Animator.upcoming state model.route then
                            Animator.Css.xy { x = -460, y = 0 }

                        else
                            Animator.Css.xy { x = 0, y = 0 }
                , Animator.Css.opacity <|
                    \state ->
                        (if Animator.upcoming state model.route then
                            Animator.at 0

                         else
                            Animator.at 1
                        )
                            |> Animator.leaveSmoothly 0
                            |> Animator.arriveSmoothly 1
                            |> Animator.arriveEarly 0.9
                ]
                [ Html.Attributes.style "inset" "0"
                , Html.Attributes.style "position" "absolute"
                ]
                [ viewRoute (Animator.arrived model.route) model
                ]
            ]
        ]
    }


viewRoute route model =
    case model.modal of
        Just (ImageModal image) ->
            viewImageModal image

        Just (AreYouSureModal label msg) ->
            viewAreYouSureModal label msg

        Nothing ->
            case route of
                MainRoute ->
                    viewMainRoute model

                AwardsRoute ->
                    viewAwardsRoute model

                PlaygroundRoute guid ->
                    let
                        playground =
                            model.playgrounds |> IdSet.toList |> List.filter (\p -> p.id == guid) |> List.head
                    in
                    case playground of
                        Just p ->
                            viewPlaygroundRoute model p

                        Nothing ->
                            Html.text <| "the playground " ++ guid ++ " does not exist"

                NewAwardRoute guid ->
                    let
                        award =
                            model.playgrounds |> allAwards |> List.filter (\a -> a.id == guid) |> List.head
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
                            model.playgrounds |> IdSet.toList |> List.filter (\p -> p.id == guid) |> List.head
                    in
                    case playground of
                        Just p ->
                            viewPlaygroundAdminRoute model p

                        Nothing ->
                            Html.text <| "the playground " ++ guid ++ " does not exist"

                MyUserRoute ->
                    viewMyUser model.user

                LoginRoute guid ->
                    viewLogin model.user guid


viewLogin maybeUser userId =
    defaultLayout <|
        column [ width fill, height fill, spacing 32, padding 22, scrollbarY ]
            [ column [ spacing 24, width fill, centerY ] <|
                case maybeUser of
                    Nothing ->
                        [ column [ width fill, spacing 16 ]
                            [ viewTitle "Du kannst jetzt als der Gescannte Nutzer loslegen."
                            , cuteButton (LoginWithId userId) <| text "Loslegen"
                            ]
                        ]

                    Just user ->
                        [ column [ width fill, spacing 16 ]
                            [ viewTitle "Du hast bereites einen Nutzer mit der folgenden ID. Willst du den überschreiben?"
                            , el [ Background.color secondaryDark, padding 8, Border.rounded 16, Font.color white, Font.size 14, centerX ] <| text user.id
                            , cuteButton (LoginWithId userId) <| text "Überschreiben"
                            ]
                        ]
            ]


viewMyUser maybeUser =
    defaultLayout <|
        column [ width fill, height fill, spacing 32, padding 22, scrollbarY ]
            [ column [ spacing 24, width fill ]
                [ viewTitle "Dein Account"
                , viewParapraph "Hier findest du alles wichtige über deinen Account. Über den QR-Code kannst du deinen Account mit einem weiteren Gerät teilen."
                ]
            , case maybeUser of
                Nothing ->
                    text "Du hast keinen Benutzer"

                Just user ->
                    let
                        url =
                            "https://magdeburger-spielplatznadel-develop.lamdera.app/login/" ++ user.id

                        userQRCode =
                            el [ width fill, height fill ] <|
                                qrCodeView <|
                                    url

                        qrBase64Png =
                            QRCode.fromString url
                                |> Result.map
                                    (QRCode.toImage >> Image.toPngUrl)
                                |> Result.withDefault ""
                    in
                    column [ width fill, height fill, spacing 16 ]
                        [ userQRCode
                        , el
                            [ Background.color secondaryDark
                            , padding 8
                            , Border.rounded 16
                            , Font.color white
                            , Font.size 14
                            , centerX
                            ]
                          <|
                            text user.id
                        , el [ height fill ] <| none
                        , shareButton
                            { files = [ qrBase64Png ]
                            , text = "Du kannst diesen Link nutzen um dich bei der Magdeburger Spielplatznadel anzumelden."
                            , title = "Anmeldung"
                            , url = url
                            }
                        ]
            ]


qrCodeView : String -> Element msg
qrCodeView message =
    QRCode.fromString message
        |> Result.map
            (QRCode.toSvg
                [-- Svg.Attributes.width "100px"
                 -- , Svg.Attributes.height "100px"
                ]
            )
        |> Result.withDefault (Html.text "Error while encoding to QRCode.")
        |> html


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
    defaultLayout <|
        el
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
    defaultLayout <|
        el
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
                    model.playgrounds |> IdSet.toList |> List.sortBy (\p -> locationDistanceInKilometers p.location geoLocation.location)

                Nothing ->
                    model.playgrounds |> IdSet.toList
    in
    defaultLayout <|
        el
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
                    [ link
                        [ padding 16
                        , Background.color secondaryDark
                        , Border.rounded 16
                        , Font.color white
                        , width fill
                        , Font.center
                        ]
                        { url = "/my-user"
                        , label =
                            text "Dein Account"
                        }
                    , link
                        [ padding 16
                        , Background.color secondaryDark
                        , Border.rounded 16
                        , Font.color white
                        , width fill
                        , Font.center
                        ]
                        { url = "/admin"
                        , label =
                            text "Admin Seite"
                        }
                    ]
                , column
                    [ spacing 16, width fill ]
                    [ el [ Font.bold ] <| text "debuggin menu"
                    , column [ spacing 8, width fill ]
                        (allAwards model.playgrounds
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


viewAwardsRoute : Model -> Html.Html msg
viewAwardsRoute model =
    let
        bound =
            el [ paddingXY 0 2, centerX, height fill ] <|
                el [ width (px 6), height fill, Background.color secondary, Border.rounded 999 ] <|
                    none

        dot =
            el [ width (px 12), height (px 12), Background.color secondaryDark, Border.rounded 999 ] <| none
    in
    defaultLayout <|
        el [ width fill, height fill, behindContent <| el [ height fill, width (px 24), padding 8 ] <| column [ centerX, height fill ] <| (List.repeat 12 dot |> List.intersperse bound) ] <|
            column [ width fill, height fill, spacing 32, padding 22, scrollbarY ]
                [ column [ spacing 24, width fill ]
                    [ viewTitle "Stempelbuch"
                    , viewParapraph "Hier findest du alle eingetragenen und austehenden Stempel."
                    ]
                , viewAwardList (model.user |> Maybe.map .awards |> Maybe.withDefault IdSet.empty) <| allAwards model.playgrounds
                ]


viewAwardList : IdSet.IdSet Award -> List Award -> Element msg
viewAwardList found awards =
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
            List.map (\award -> viewAward offX offY (IdSet.member award found) award) awards



-- TODO map the user to the awards collected state


viewNewAwardRoute model award =
    defaultLayout <|
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
                [ el [ centerX, paddingXY 0 70, scale 1.7 ] <| viewAward 8 4 True award
                ]
            ]


viewPlaygroundRoute : Model -> Playground -> Html.Html FrontendMsg
viewPlaygroundRoute model playground =
    defaultLayout <|
        column [ width fill, height fill, spacing 32, padding 22, scrollbarY ]
            [ el [ Font.color secondaryDark, centerX ] <| iconSized Icons.toys 64
            , column [ spacing 32, width fill ]
                [ viewTitle playground.title
                , viewParapraph playground.description
                ]
            , viewImageStrip playground.images
            , column [ spacing 16, width fill ] [ viewAwardList (model.user |> Maybe.map .awards |> Maybe.withDefault IdSet.empty) playground.awards ]
            , mapCollapsed playground
            ]



-- TODO remove stuff like playgrounds


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
    defaultLayout <|
        column [ width fill, height fill, spacing 32, padding 22, scrollbarY ]
            [ column [ spacing 24, width fill ]
                [ viewTitle "Admin Seite"
                , viewParapraph "Hier kannst du alles einstellen"
                ]
            , column
                [ spacing 16, width fill ]
                ((model.playgrounds |> IdSet.toList |> List.map playgroundAdminItem) ++ [ addPlaygroundButton ])
            ]


viewPlaygroundAdminRoute : Model -> Playground -> Html.Html FrontendMsg
viewPlaygroundAdminRoute model playground =
    let
        adminGeneral =
            column [ spacing 32, width fill ]
                [ cuteInput "Titel des Spielplatzes" playground.title <| \v -> UpdatePlayground { playground | title = v }
                , cuteInputMultiline "Beschreibung des Spielpatzes" playground.description <| \v -> UpdatePlayground { playground | description = v }
                ]

        imageUpload =
            cuteButton (ImageRequested <| PlaygroundImageTarget playground) <| text "Bild hochladen"

        viewImagesAdmin : List Img -> Element FrontendMsg
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
            imageUpload

        -- Input.button
        --     [ width fill
        --     , Border.rounded 16
        --     , Background.color secondary
        --     , width fill
        --     , height (px 64)
        --     , paddingXY 24 0
        --     , Font.color secondaryDark
        --     ]
        --     { onPress = Just <| UpdatePlayground { playground | images = playground.images ++ [ { url = "", description = "" } ] }
        --     , label = row [ centerX, centerY, spacing 8 ] [ icon Icons.add, icon Icons.image ]
        --     }
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
                    [ viewAward 8 8 True award
                    , viewAward 8 8 False award
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

        viewDeleteButton =
            cuteButton (RemovePlaygroundLocal playground) <| row [] [ icon Icons.delete, text "Speilplatz löschen" ]
    in
    defaultLayout <|
        column
            [ width fill, height fill, spacing 128, padding 22, scrollbarY ]
            ([ el [ Font.color secondaryDark, centerX ] <| iconSized Icons.toys 64
             , adminGeneral
             , viewMarkerAdmin playground.markerIcon
             , viewImagesAdmin playground.images
             , column [ spacing 16, width fill ] <|
                (List.map viewAwardItemAdmin playground.awards ++ [ addAwardButton ])
             , adminMapWithLocation
             , viewDeleteButton
             ]
             -- |> List.intersperse (el [ width fill, height (px 32), Background.color secondary, alpha 0.1 ] <| none)
            )


defaultLayout =
    layoutWith { options = [ noStaticStyleSheet ] }
        [ width fill, height fill ]
        << el
            [ width <| maximum 480 <| fill
            , height fill
            , centerX

            -- , Border.shadow { offset = ( 0, 0 ), size = 0, blur = 64, color = rgba 0 0 0 0.2 }
            ]


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


initAward : Seeds -> ( Award, Seeds )
initAward s1 =
    IdSet.assignId
        ( { title = ""
          , id = IdSet.nilId
          , image =
                { url = ""
                , description = ""
                }
          }
        , s1
        )


playgroundMarker : Playground -> Marker
playgroundMarker playground =
    { location = playground.location
    , icon = playground.markerIcon
    , popupText = playground.title
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


shareButton shareData =
    cuteButton (Share shareData) <| row [ spacing 8 ] [ icon Icons.share, text "Teilen" ]



-- Ports


port geoLocationUpdated : (String -> msg) -> Sub msg


port geoLocationError : (String -> msg) -> Sub msg


port storageLoaded : (Maybe String -> msg) -> Sub msg


port saveStorage : String -> Cmd msg


port share : ShareData -> Cmd msg



-- Subscriptions


subscriptions model =
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
        , storageLoaded StorageLoaded
        , animator |> Animator.toSubscription Tick model
        ]


animator : Animator.Animator Model
animator =
    Animator.animator
        -- *NOTE*  We're using `the Animator.Css.watching` instead of `Animator.watching`.
        -- Instead of asking for a constant stream of animation frames, it'll only ask for one
        -- and we'll render the entire css animation in that frame.
        |> Animator.Css.watching .route
            (\newRoute_ model ->
                { model | route = newRoute_ }
            )



-- Elements


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
        , placeholder = Just <| Input.placeholder [] <| text "..."
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
        , placeholder = Just <| Input.placeholder [] <| text "..."
        , label = Input.labelHidden label
        , spellcheck = True
        }


cuteButton onPress label =
    Input.button
        [ width fill
        , Border.rounded 16
        , Background.color secondary
        , width fill
        , height (px 64)
        , paddingXY 24 0
        , Font.color secondaryDark
        ]
        { onPress = Just onPress
        , label = el [ centerX, centerY ] <| label
        }


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


viewAward : Float -> Float -> Bool -> Award -> Element msg
viewAward offX offY found award =
    let
        new =
            False

        got =
            found

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
        , UP.map MyUserRoute (UP.s "my-user")
        , UP.map LoginRoute (UP.s "login" </> UP.string)
        , UP.map PlaygroundAdminRoute (UP.s "admin" </> UP.s "playground" </> UP.string)
        ]


wrapInAreYouSure label msg =
    OpenModal <| AreYouSureModal label <| msg


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
