module Types exposing (..)

import Browser exposing (UrlRequest)
import Browser.Navigation as Nav
import Lamdera exposing (ClientId)
import Set exposing (Set)
import Time exposing (Posix)
import UUID
import Url exposing (Url)



-- Models


type alias FrontendModel =
    { key : Nav.Key
    , route : Route
    , online : Bool
    , playgrounds : List Playground
    , myLocation : Maybe Location
    , modal : Maybe Modal
    , seeds : UUID.Seeds
    }


type Modal
    = ImageModal Image


type Route
    = MainRoute
    | PlaygroundRoute Guid
    | AwardsRoute
    | NewAwardRoute Guid
    | AdminRoute
    | PlaygroundAdminRoute Guid


type alias Playground =
    { id : Guid
    , title : String
    , description : String
    , location : Location
    , images : List Image
    , awards : List Award
    , markerIcon : MarkerIcon
    }


type alias Award =
    { id : Guid
    , title : String
    , image : Image
    , found : Maybe Posix
    }


type alias Image =
    { url : String
    , description : String

    -- TODO size
    -- TODO blur hash
    }


type alias LeafletMapConfig =
    { camera : Camera
    , markers : List Marker
    , onClick : Maybe (Location -> FrontendMsg)
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
    }


type alias Location =
    { lat : Float
    , lng : Float
    }


type alias Guid =
    String


type alias BackendModel =
    { playgrounds : List Playground
    , connected : Set ClientId
    }



-- Msg's


type FrontendMsg
    = UrlClicked UrlRequest
    | UrlChanged Url
    | Online Bool
    | ReplaceUrl String
    | OpenImageModal Image
    | CloseModal
    | NoOpFrontendMsg
    | UpdatePlayground Playground
    | AddAward Playground
    | AddPlayground



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
    | FetchPlaygrounds


type BackendMsg
    = NoOpBackendMsg
    | ClientConnected ClientId
    | ClientDisconnected ClientId


type ToFrontend
    = NoOpToFrontend
    | PlaygroundUploaded Playground
    | PlaygroundsFetched (List Playground)
