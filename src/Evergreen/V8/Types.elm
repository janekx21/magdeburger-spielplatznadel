module Evergreen.V8.Types exposing (..)

import Browser
import Browser.Navigation
import Url


type Route
    = MainRoute
    | PlaygroundRoute String
    | AwardsRoute
    | NewAwardRoute String
    | AdminRoute


type alias Guid =
    String


type alias Location =
    { lat : Float
    , lng : Float
    }


type alias Image =
    { url : String
    , description : String
    }


type alias Playground =
    { id : Guid
    , title : String
    , location : Location
    , images : List Image
    }


type Modal
    = ImageModal Image


type alias FrontendModel =
    { key : Browser.Navigation.Key
    , route : Route
    , online : Bool
    , playgrounds : List Playground
    , myLocation : Maybe Location
    , modal : Maybe Modal
    }


type alias BackendModel =
    { message : String
    }


type FrontendMsg
    = UrlClicked Browser.UrlRequest
    | UrlChanged Url.Url
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
