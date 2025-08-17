module Types exposing (..)

import Animator
import Browser exposing (UrlRequest)
import Browser.Navigation as Nav
import Bytes exposing (Bytes)
import Dict exposing (Dict)
import File exposing (File)
import Http
import IdSet exposing (..)
import Json.Decode as D
import Lamdera exposing (ClientId, SessionId)
import Time
import UUID
import Url exposing (Url)



-- Models


type alias FrontendModel =
    { key : Nav.Key
    , route : Animator.Timeline Route
    , online : Bool
    , playgrounds : IdSet Playground
    , currentGeoLocation : Maybe GeoLocation
    , snapGeoLocation : Bool
    , mapCamera : Camera
    , modal : Maybe Modal
    , seeds : UUID.Seeds
    , user : Maybe User
    , deleteHashes : Dict Link DeleteHash
    , focusedPlayground : Maybe Playground
    }


type Modal
    = ImageModal Img
    | AreYouSureModal String FrontendMsg


type Route
    = MainRoute
    | PlaygroundRoute Guid
    | AwardsRoute
    | NewAwardRoute Guid
    | AdminRoute
    | PlaygroundAdminRoute Guid
    | MyUserRoute
    | LoginRoute Guid


type alias Playground =
    { id : Guid
    , title : String
    , description : String
    , location : Location
    , images : List Img
    , awards : List Award
    , markerIcon : MarkerIcon
    }


type alias Award =
    { id : Guid
    , title : String
    , image : Img
    , transform : Transform
    }


type alias Transform =
    { x : Float
    , y : Float
    , rotation : Float
    }


type alias Img =
    { url : Link

    -- TODO size
    -- TODO blur hash
    }


type alias LeafletMapConfig =
    { camera : Camera
    , markers : List Marker
    , onClick : Maybe (Location -> FrontendMsg)
    , onMove : Maybe (Camera -> FrontendMsg)
    , onMarkerClick : Maybe (Marker -> FrontendMsg)
    }


type alias Camera =
    { location : Location
    , zoom : Int
    }


type alias MarkerIcon =
    { url : String
    , shadowUrl : String
    }


type alias Marker =
    { location : Location
    , icon : MarkerIcon
    , popupText : String
    , opacity : Float
    }


type alias Location =
    { lat : Float
    , lng : Float
    }


{-| <https://wiki.selfhtml.org/wiki/JavaScript/Geolocation>
-}
type alias GeoLocation =
    { location : Location
    , heading : Maybe Float
    }


type alias Guid =
    String


type alias BackendModel =
    { playgrounds : IdSet Playground
    , connections : IdSet Connection
    , users : IdSet User
    , deleteHashes : Dict Link DeleteHash
    }


type alias Connection =
    { id : ClientId
    , userId : Maybe Guid
    }


type alias UserId =
    Guid


type alias User =
    { id : UserId
    , awards : IdSet Award
    , role : Role
    }


type Role
    = RegularUser
    | Moderator
    | Admin



-- Msg's


type FrontendMsg
    = UrlClicked UrlRequest
    | UrlChanged Url
    | Online Bool
    | ReplaceUrl String
    | OpenModal Modal
    | CloseModal
    | CloseModalAnd FrontendMsg
    | NoOpFrontendMsg
    | UpdatePlayground Playground
    | RemovePlaygroundImage Playground Int
    | AddAward Playground
    | AddPlayground
    | RemovePlaygroundLocal Playground
    | GeoLocationUpdated (Maybe GeoLocation)
    | StorageLoaded (Maybe String)
    | LoginWithId UserId
    | SetSeed UUID.Seeds
    | Share ShareData
    | ImageRequested ImageTarget
    | ImageSelected ImageTarget File
    | ImageUploaded ImageTarget (Result Http.Error ImgurImage)
    | ImageDeleted (Result Http.Error ())
    | Tick Time.Posix
    | SnapToLocation
    | CameraMoved Camera
    | MarkerClicked Marker
    | UnfocusPlayground


type alias Link =
    String


type alias ImgurId =
    String


type alias DeleteHash =
    String


type alias ImgurImage =
    { id : ImgurId, link : Link, deleteHash : DeleteHash }


type alias ShareData =
    { -- base64 encoded blobs
      files : List String
    , text : String
    , title : String
    , url : String
    }


type ImageTarget
    = PlaygroundImageTarget Playground



--    | RouteMsg RouteMsg


{-|

    This Message gets triggered when a route sends a message.
    The great thing is that type names and constructors do not collide

-}



--type RouteMsg
--    = PlaygroundAdminRouteMsg PlaygroundAdminRouteMsg
--type PlaygroundAdminRouteMsg
--    = MapClicked Location


type ToBackend
    = NoOpToBackend
    | UploadPlayground Playground
    | RemovePlayground Playground
    | Collect Guid
    | SetConnectedUser UserId
    | UploadImage Bytes
    | AddDeleteHash Link DeleteHash


type BackendMsg
    = NoOpBackendMsg
    | ClientConnected SessionId ClientId
    | ClientDisconnected ClientId



-- | ImageUploaded (Result Http.Error String)


type ToFrontend
    = NoOpToFrontend
    | PlaygroundUploaded Playground
    | PlaygroundRemoved Playground -- TODO can this be added to playground uploaded?
    | PlaygroundsFetched (List Playground)
    | UserUpdated User
    | UserLoggedIn
    | DeleteHashUpdated (Dict Link DeleteHash)
