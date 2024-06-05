module Types exposing (..)

import Browser exposing (UrlRequest)
import Browser.Navigation as Nav
import Url exposing (Url)



-- Models


type alias FrontendModel =
    { key : Nav.Key
    , route : Route
    , online : Bool
    , playgrounds : List Playground
    , myLocation : Maybe Location
    , modal : Maybe Modal
    }


type Modal
    = ImageModal Image


type Route
    = MainRoute
    | PlaygroundRoute String
    | AwardsRoute
    | NewAwardRoute String
    | AdminRoute


type alias Playground =
    { id : Guid
    , title : String
    , location : Location
    , images : List Image
    }


type alias Image =
    { url : String
    , description : String
    }


type alias LeafletMapConfig =
    { camera : Camera
    , markers : List Location
    }


type alias Camera =
    { location : Location
    , zoom : Int
    }


type alias Location =
    { lat : Float
    , lng : Float
    }


type alias Guid =
    String


type alias BackendModel =
    { message : String
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


type ToBackend
    = NoOpToBackend


type BackendMsg
    = NoOpBackendMsg


type ToFrontend
    = NoOpToFrontend
