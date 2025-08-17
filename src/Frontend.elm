port module Frontend exposing (app)

import Animator
import Animator.Css
import Browser exposing (UrlRequest(..))
import Browser.Navigation as Nav
import Common exposing (..)
import Dict
import Element exposing (..)
import Element.Background as Background
import Element.Border as Border exposing (rounded)
import Element.Events
import Element.Font as Font
import Element.Input as Input
import Env
import File
import File.Select as Select
import Html
import Html.Attributes
import Html.Events
import Html.Keyed
import Http
import IdSet
import Json.Decode as D
import Json.Encode as E
import Lamdera
import Material.Icons as Icons
import Material.Icons.Types exposing (Icon)
import QRCode
import Random
import Types exposing (..)
import UUID exposing (Seeds)
import Url
import Url.Parser as UP exposing ((</>), Parser, oneOf)



-- TODO Url.Builder


type alias Model =
    FrontendModel


app : { init : Lamdera.Url -> Nav.Key -> ( FrontendModel, Cmd FrontendMsg ), view : FrontendModel -> Browser.Document FrontendMsg, update : FrontendMsg -> FrontendModel -> ( FrontendModel, Cmd FrontendMsg ), updateFromBackend : ToFrontend -> FrontendModel -> ( FrontendModel, Cmd FrontendMsg ), subscriptions : FrontendModel -> Sub FrontendMsg, onUrlRequest : UrlRequest -> FrontendMsg, onUrlChange : Url.Url -> FrontendMsg }
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
      , route = Animator.init route |> Animator.go Animator.veryQuickly route
      , online = True
      , currentGeoLocation = Nothing
      , modal = Nothing

      -- the seeds are just a placeholder that will be overriten as soon as possible
      , seeds = UUID.Seeds (Random.initialSeed 1) (Random.initialSeed 2) (Random.initialSeed 3) (Random.initialSeed 4)
      , playgrounds = IdSet.empty
      , user = Nothing
      , snapGeoLocation = False
      , mapCamera = { location = magdeburg, zoom = 12 }
      , deleteHashes = Dict.empty
      , focusedPlayground = Nothing
      }
        |> updateMiddleware route
    , Random.generate SetSeed (Random.map4 UUID.Seeds seed seed seed seed)
      -- collect stuff after loggin in
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
                                    Cmd.batch
                                        [ Lamdera.sendToBackend <| Collect guid
                                        ]

                                _ ->
                                    Cmd.none
                    in
                    ( newRoute url model |> updateMiddleware route
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
            updatePlayground model playground

        RemovePlaygroundImage playground index ->
            let
                maybeHash =
                    getItemInList playground.images index
                        |> Maybe.andThen (\img -> Dict.get img.url model.deleteHashes)
            in
            case maybeHash of
                Just hash ->
                    let
                        delteCmd =
                            imageDeleteCmd hash

                        ( updateModel, updateCmd ) =
                            updatePlayground model { playground | images = removeInList playground.images index }
                    in
                    ( updateModel, Cmd.batch [ updateCmd, delteCmd ] )

                Nothing ->
                    ( model, Cmd.none )

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
            ( model
            , Cmd.batch
                [ saveStorage userId
                , Lamdera.sendToBackend <|
                    SetConnectedUser userId
                ]
            )

        LoginWithId userId ->
            ( model
            , Cmd.batch [ Nav.replaceUrl model.key "/", Lamdera.sendToBackend <| SetConnectedUser userId, saveStorage userId ]
            )

        SetSeed seeds ->
            ( { model | seeds = seeds }, Cmd.none )

        Share data ->
            ( model, share data )

        ImageRequested target ->
            ( model, Select.file [ "image/*" ] (ImageSelected target) )

        ImageSelected target file ->
            ( model
            , imageUploadCmd target file
            )

        ImageUploaded target result ->
            case result of
                Ok imgurImage ->
                    case target of
                        PlaygroundImageTarget playground ->
                            let
                                ( updateModel, updateCmd ) =
                                    updatePlayground model { playground | images = playground.images ++ [ { url = imgurImage.link } ] }
                            in
                            ( updateModel, Cmd.batch [ updateCmd, Lamdera.sendToBackend (AddDeleteHash imgurImage.link imgurImage.deleteHash) ] )

                Err err ->
                    ( model, Cmd.none )

        ImageDeleted result ->
            let
                _ =
                    Debug.log "ImageDeleted" result
            in
            case result of
                Ok _ ->
                    ( model, Cmd.none )

                Err _ ->
                    ( model, Cmd.none )

        Tick newTime ->
            ( Animator.update newTime animator model, Cmd.none )

        SnapToLocation ->
            ( { model | snapGeoLocation = True }, Cmd.none )

        CameraMoved camera ->
            ( { model | mapCamera = camera, snapGeoLocation = Just camera.location == (model.currentGeoLocation |> Maybe.map .location) }, Cmd.none )

        MarkerClicked marker ->
            ( { model | focusedPlayground = model.playgrounds |> IdSet.toList |> List.filter (\p -> p.location == marker.location) |> List.head, mapCamera = { location = marker.location, zoom = 14 }, snapGeoLocation = False }, Cmd.none )

        UnfocusPlayground ->
            ( { model | focusedPlayground = Nothing }, Cmd.none )



-- Use this to inject some additional state
-- that is url dependent into the model on a route change


updateMiddleware : Route -> Model -> Model
updateMiddleware route m =
    case route of
        PlaygroundRoute guid ->
            { m | focusedPlayground = m.playgrounds |> IdSet.get guid }

        MainRoute ->
            case m.focusedPlayground of
                Nothing ->
                    m

                Just p ->
                    { m | mapCamera = { location = p.location, zoom = 14 } }

        _ ->
            m


updatePlayground model playground =
    ( { model | playgrounds = model.playgrounds |> IdSet.insert playground }, Lamdera.sendToBackend <| UploadPlayground playground )


newRoute : Url.Url -> Model -> Model
newRoute url model =
    { model
        | route =
            model.route
                |> Animator.go (Animator.millis 150) (parseUrl url)

        -- |> Animator.go (Animator.millis 5000) (parseUrl url)
    }


imageUploadCmd : ImageTarget -> File.File -> Cmd FrontendMsg
imageUploadCmd target file =
    Http.request
        { method = "POST"
        , headers =
            [ Http.header "Authorization" "Client-ID d39e7a51841a2f1"
            ]
        , url = "https://api.imgur.com/3/image"
        , expect = Http.expectJson (ImageUploaded target) imgurImageDecoder
        , timeout = Nothing
        , tracker = Nothing
        , body =
            Http.multipartBody
                [ Http.stringPart "title" "simple image number one"
                , Http.stringPart "description" "simple description number two"
                , Http.filePart "image" file
                , Http.stringPart "type" "file"
                ]
        }



{--
-- TODO example image

{
    "id": "kZbTHiA",
    "deletehash": "VNqYAk7BQvBJ3wU",
    "account_id": null,
    "account_url": null,
    "ad_type": null,
    "ad_url": null,
    "title": "simple image",
    "description": "simple description",
    "name": "",
    "type": "image/png",
    "width": 200,
    "height": 200,
    "size": 4040,
    "views": 0,
    "section": null,
    "vote": null,
    "bandwidth": 0,
    "animated": false,
    "favorite": false,
    "in_gallery": false,
    "in_most_viral": false,
    "has_sound": false,
    "is_ad": false,
    "nsfw": null,
    "link": "https://i.imgur.com/kZbTHiA.png",
    "tags": [],
    "datetime": 1735225135,
    "mp4": "",
    "hls": ""

}


{
  "id": "zebTRlF",
  "deletehash": "IfpCBzk9ek51Rh1",
  "account_id": null,
  "account_url": null,
  "ad_type": null,
  "ad_url": null,
  "title": "simple image number one",
  "description": "simple description number two",
  "name": "",
  "type": "image/png",
  "width": 1024,
  "height": 1024,
  "size": 118452,
  "views": 0,
  "section": null,
  "vote": null,
  "bandwidth": 0,
  "animated": false,
  "favorite": false,
  "in_gallery": false,
  "in_most_viral": false,
  "has_sound": false,
  "is_ad": false,
  "nsfw": null,
  "link": "https://i.imgur.com/zebTRlF.png",
  "tags": [],
  "datetime": 1735338374,
  "mp4": "",
  "hls": ""
}

https://i.imgur.com/NdwP8Oj.jpeg
Ich hab mir den delete hash durch die lappen gehen lassen :<


--}


imgurImageDecoder : D.Decoder ImgurImage
imgurImageDecoder =
    D.field "data"
        (D.map3 ImgurImage
            (D.field "id" <| D.string)
            (D.field "link" <| D.string)
            (D.field "deletehash" <| D.string)
        )


imageDeleteCmd : DeleteHash -> Cmd FrontendMsg
imageDeleteCmd hash =
    Http.request
        { method = "DELETE"
        , headers =
            [ Http.header "Authorization" "Client-ID d39e7a51841a2f1"
            ]
        , url = "https://api.imgur.com/3/image/" ++ hash
        , expect = Http.expectWhatever ImageDeleted
        , timeout = Nothing
        , tracker = Nothing
        , body = Http.emptyBody
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

        UserLoggedIn ->
            let
                collectCmd =
                    case model.route |> Animator.current of
                        NewAwardRoute guid ->
                            Lamdera.sendToBackend <| Collect guid

                        _ ->
                            Cmd.none
            in
            ( model, collectCmd )

        DeleteHashUpdated deleteHashes ->
            ( { model | deleteHashes = deleteHashes }, Cmd.none )



-- View


view : Model -> Browser.Document FrontendMsg
view model =
    { title = ""
    , body =
        -- The flex box will enlarge from the flex-basis. This needs to be disabled on scolling content
        [ Html.node "style" [] [ Html.text ".s.sby {flex-basis: 0 !important;}" ]
        , Html.Keyed.node "div"
            [ Html.Attributes.style "height" "100%"
            , Html.Attributes.style "width" "100%"
            , Html.Attributes.style "position" "relative"
            , Html.Attributes.style "overflow" "hidden"
            ]
          <|
            -- TODO try layout and Animator.linear
            -- https://korban.net/posts/elm/2020-04-07-using-elm-animator-with-elm-ui/
            [ ( "layout", layout [] <| none )

            -- NEW STATE
            , ( Animator.current model.route |> showRoute
              , Animator.Css.div model.route
                    [ Animator.Css.transform <|
                        \state ->
                            if Animator.upcoming state model.route then
                                Animator.Css.xy { x = 0, y = 0 }

                            else
                                Animator.Css.xy { x = 50, y = 0 }
                    , Animator.Css.opacity <|
                        \state ->
                            if Animator.upcoming state model.route then
                                Animator.at 1

                            else
                                Animator.at 0

                    -- |> Animator.leaveSmoothly 0
                    -- |> Animator.arriveSmoothly 1
                    ]
                    [ Html.Attributes.style "inset" "0"
                    , Html.Attributes.style "position" "absolute"
                    ]
                    [ viewRoute (Animator.current model.route) model
                    ]
              )
            ]
                -- OLD STATE
                -- ++ (if Animator.upcoming (Animator.current model.route) model.route || Animator.previous model.route == Animator.current model.route then
                ++ [ ( Animator.arrived model.route |> showRoute
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
                        , Html.Attributes.style "pointer-events" "none"
                        ]
                        [ viewRoute (Animator.arrived model.route) model
                        ]
                       -- , layout [] <| text "hi i am old"
                     )
                   ]

        -- else
        --     []
        -- )
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
                            model.playgrounds |> IdSet.get guid
                    in
                    case playground of
                        Just p ->
                            viewPlaygroundRoute model p

                        Nothing ->
                            Html.text <| "the playground for " ++ guid ++ " does not exist"

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
                            Html.text <| "the playground admin page for " ++ guid ++ " does not exist"

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
                            Env.absoluteBaseUrl ++ "login/" ++ user.id

                        userQRCode =
                            el [ width fill, height fill ] <|
                                qrCodeView <|
                                    url

                        -- qrBase64Png =
                        --     QRCode.fromString url
                        --         |> Result.map
                        --             (QRCode.toImage >> Image.toPngUrl)
                        --         |> Result.withDefault ""
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

                        -- , shareButton
                        --     { files = [] -- qrBase64Png
                        --     , text = "Du kannst diesen Link nutzen um dich bei der Magdeburger Spielplatznadel anzumelden."
                        --     , title = "Anmeldung"
                        --     , url = url
                        --     }
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
                    { src = i.url, description = "image of a playground" }
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

        location =
            Maybe.map .location model.currentGeoLocation

        seperator =
            el [ height (px 64), width fill ] <| el [ Font.color secondary, centerX, centerY ] <| text "..."
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
                , mainMap
                    (Maybe.map .location model.currentGeoLocation)
                    (List.map
                        (\p ->
                            playgroundMarker
                                (case model.focusedPlayground of
                                    Nothing ->
                                        True

                                    Just focused ->
                                        p == focused
                                )
                                p
                        )
                        playgrounds
                    )
                    model.snapGeoLocation
                    model.mapCamera
                , column
                    [ spacing 16, width fill ]
                    (case model.focusedPlayground of
                        Nothing ->
                            playgrounds |> List.map (playgroundItem location)

                        Just playground ->
                            playgroundItemExpanded location playground
                                :: seperator
                                :: (playgrounds |> List.filter (\p -> p /= playground) |> List.map (playgroundItem location))
                    )
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
                    , ifUserCanRole model.user
                        Moderator
                        (link
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
                        )
                        none
                    ]
                , ifUserCanRole model.user
                    Admin
                    (column
                        [ spacing 16, width fill ]
                        [ el [ Font.bold ] <| text "debuggin menu"
                        , column [ spacing 8, width fill ]
                            (allAwards model.playgrounds
                                |> List.map
                                    (\{ id, title } ->
                                        link [ width fill ]
                                            { url = showRoute <| NewAwardRoute id
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
                    )
                    none
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
    if List.isEmpty awards then
        row [ Font.color secondaryDark, spacing 8 ] [ text "Hier gibt es keine Stempel", icon Icons.sentiment_dissatisfied ]

    else
        row
            [ width fill, style "flex-wrap" "wrap", style "gap" "32px", justifyCenter ]
        <|
            List.map (\award -> viewAward (IdSet.member award found) award) awards



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
                [ el [ centerX, paddingXY 0 70, scale 1.7 ] <| viewAward True award
                ]
            ]


viewPlaygroundRoute : Model -> Playground -> Html.Html FrontendMsg
viewPlaygroundRoute model playground =
    let
        absoluteUrl =
            Env.absoluteBaseUrl ++ (showRoute <| PlaygroundRoute playground.id)
    in
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
            , shareButton { files = [], title = "Spielpatz " ++ playground.title, text = "Spielplatz in der Magdeburger Spielpatznadel\n\nTitel: " ++ playground.title ++ "\n-------\n" ++ playground.description ++ "\n\nLink: " ++ absoluteUrl, url = absoluteUrl }
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
                                    , inFront <| el [ moveUp 18, moveLeft 18 ] <| removeButton (RemovePlaygroundImage playground index)
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
            let
                awardImage =
                    award.image
            in
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
                    [ viewAward True award
                    , viewAward False award
                    ]
                , cuteInput "Titel" award.title <| \v -> UpdatePlayground { playground | awards = playground.awards |> updateListItemViaId { award | title = v } }
                , cuteInput "Bild URL" award.image.url <| \v -> UpdatePlayground { playground | awards = playground.awards |> updateListItemViaId { award | image = { awardImage | url = v } } }
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
                    , markers = [ playgroundMarker True playground ]
                    , onClick = Just <| \v -> UpdatePlayground { playground | location = v }
                    , onMove = Nothing
                    , onMarkerClick = Nothing
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
    let
        ( transform, _ ) =
            Random.step generateTransform s1.seed1
    in
    IdSet.assignId
        ( { title = ""
          , id = IdSet.nilId
          , image = { url = "" }
          , transform = transform
          }
        , s1
        )


generateTransform : Random.Generator Transform
generateTransform =
    Random.map3 Transform (Random.float -16 16) (Random.float -16 16) (Random.float -0.1 0.1)


playgroundMarker : Bool -> Playground -> Marker
playgroundMarker active playground =
    { location = playground.location
    , icon = playground.markerIcon

    -- , popupText = "<a href=\"" ++ (showRoute <| PlaygroundRoute playground.id) ++ "\" rel=\"noopener noreferrer\">" ++ playground.title ++ "</a>"
    , popupText = playground.title
    , opacity =
        if active then
            1.0

        else
            0.35
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


shareButton : ShareData -> Element FrontendMsg
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
        -- |> Animator.watching .route
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


mainMap : Maybe Location -> List Marker -> Bool -> Camera -> Element FrontendMsg
mainMap location marker snap mapCamera =
    let
        lockButton =
            el [ alignBottom, alignRight, padding 8 ] <|
                Input.button
                    [ padding 8
                    , Background.color white
                    , Font.color primary
                    , Border.rounded 999
                    , Border.shadow { offset = ( 0, 2 ), size = 0, blur = 9, color = rgba 0 0 0 0.25 }
                    ]
                    { label = iconSized Icons.my_location 32
                    , onPress = Just SnapToLocation
                    }

        camera =
            if snap then
                { location = location |> Maybe.withDefault magdeburg
                , zoom = 14
                }

            else
                mapCamera

        selfMarkerIcon =
            { url = "/assets/images/self.svg", shadowUrl = "/assets/images/self_shadow.png" }

        selfMarker : Location -> Marker
        selfMarker loc =
            { location = loc, icon = selfMarkerIcon, popupText = "", opacity = 1.0 }

        markersAndSelf =
            marker |> maybeConcat (location |> Maybe.map selfMarker)
    in
    el
        [ width fill
        , square
        , flexBasisAuto
        , Border.rounded 16
        , style "overflow" "hidden"
        , inFront <| maybeNone <| (location |> Maybe.map (\_ -> lockButton))
        ]
    <|
        leafletMap
            { camera = camera
            , markers = markersAndSelf
            , onClick = Just <| \_ -> UnfocusPlayground
            , onMove = Just <| CameraMoved
            , onMarkerClick = Just <| MarkerClicked
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
        leafletMap { camera = { location = playground.location, zoom = 14 }, markers = [ playgroundMarker True playground ], onClick = Nothing, onMove = Nothing, onMarkerClick = Nothing }


leafletMap : LeafletMapConfig -> Element FrontendMsg
leafletMap config =
    el [ behindContent <| el [ Background.image "/assets/images/map_background.jpg", width fill, height fill ] none, height fill, width fill ] <|
        html <|
            Html.node "leaflet-map"
                ([ Html.Attributes.attribute "data" (E.encode 0 (encodeLeafletMapConfig config))
                 , Html.Attributes.style "height" "100%"
                 , Html.Attributes.style "background" "transparent"
                 ]
                    |> maybeConcat (config.onClick |> Maybe.map (\msg -> Html.Events.on "click_elm" (D.map msg (decodeDetail decodeLocation))))
                    |> maybeConcat (config.onMove |> Maybe.map (\msg -> Html.Events.on "moveend_elm" (D.map msg (decodeDetail decodeCamera))))
                    |> maybeConcat (config.onMarkerClick |> Maybe.map (\msg -> Html.Events.on "click_marker_elm" (D.map msg (decodeDetail decodeMarker))))
                )
                []


maybeConcat : Maybe a -> List a -> List a
maybeConcat maybeItem list =
    case maybeItem of
        Nothing ->
            list

        Just item ->
            list ++ [ item ]


maybeNone : Maybe (Element a) -> Element a
maybeNone may =
    case may of
        Nothing ->
            none

        Just element ->
            element


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
                , location |> Maybe.map (viewDistance playground.location) |> Maybe.withDefault none
                ]
        , url = showRoute <| PlaygroundRoute playground.id
        }


playgroundItemExpanded : Maybe Location -> Playground -> Element msg
playgroundItemExpanded location playground =
    link
        [ Border.rounded 16
        , Background.color secondary
        , width fill
        , paddingXY 24 20
        ]
    <|
        { label =
            column [ Font.color secondaryDark, spacing 16 ]
                [ row [ centerY, width fill, spacing 8 ]
                    [ icon Icons.toys
                    , textTruncated playground.title
                    , location |> Maybe.map (viewDistance playground.location) |> Maybe.withDefault none
                    ]
                , paragraph [ width fill ] [ text playground.description ]
                , if List.isEmpty playground.awards then
                    none

                  else
                    row [ spacing 8 ] (playground.awards |> List.map (\_ -> emptyEl [ rounded 99, Background.color secondaryDark, width (px 16), height (px 16) ]))
                ]
        , url = showRoute <| PlaygroundRoute playground.id
        }


viewDistance from to =
    let
        km =
            locationDistanceInKilometers from to

        kmString =
            toFloat (round (km * 100)) / 100 |> String.fromFloat
    in
    el [ alignRight, itim, Font.size 24 ] <|
        text <|
            (kmString ++ "km")


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


viewAward : Bool -> Award -> Element msg
viewAward found award =
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
                , moveRight award.transform.x
                , moveDown award.transform.x
                , rotate award.transform.rotation
                , scale 1.1
                , style "mask" "url(\"/assets/images/dust_mask.png\") center center / cover no-repeat luminance"
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
        [ Background.color primaryDark
        , Border.rounded 999
        , padding 16
        , Font.color white
        , Border.shadow
            { offset = ( 0, 4 )
            , size = 0
            , blur = 18
            , color = rgba 0.05 0.2 0.1 0.25
            }
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


showRoute : Route -> String
showRoute route =
    case route of
        MainRoute ->
            ""

        PlaygroundRoute guid ->
            "playground/" ++ guid

        AwardsRoute ->
            "award"

        NewAwardRoute guid ->
            "new-award/" ++ guid

        AdminRoute ->
            "admin"

        PlaygroundAdminRoute guid ->
            "admin/playground/" ++ guid

        MyUserRoute ->
            "my-user"

        LoginRoute guid ->
            "login/" ++ guid


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
        , ( "opacity", E.float marker.opacity )
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


decodeCamera : D.Decoder Camera
decodeCamera =
    D.map2 Camera
        (D.field "location" decodeLocation)
        (D.field "zoom" D.int)


decodeGeoLocation : D.Decoder GeoLocation
decodeGeoLocation =
    D.map2 GeoLocation
        (D.field "location" decodeLocation)
        (D.maybe <| D.field "heading" D.float)


decodeMarker : D.Decoder Marker
decodeMarker =
    D.map4 Marker
        (D.field "location" decodeLocation)
        (D.field "icon" decodeMarkerIcon)
        (D.field "popupText" D.string)
        (D.field "opacity" D.float)


decodeMarkerIcon : D.Decoder MarkerIcon
decodeMarkerIcon =
    D.map2 MarkerIcon
        (D.field "url" D.string)
        (D.field "shadowUrl" D.string)


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


ifUserCanRole maybeUser role good bad =
    if maybeUser |> Maybe.map (userCanRole role) |> Maybe.withDefault False then
        good

    else
        bad



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


primaryDark =
    rgb255 112 205 58


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
