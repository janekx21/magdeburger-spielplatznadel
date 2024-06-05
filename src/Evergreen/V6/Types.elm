module Evergreen.V6.Types exposing (..)

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


type alias Playground =
    { id : Guid
    , title : String
    , location : Location
    }


type alias FrontendModel =
    { key : Browser.Navigation.Key
    , route : Route
    , online : Bool
    , playgrounds : List Playground
    , myLocation : Maybe Location
    }


type alias BackendModel =
    { message : String
    }


type FrontendMsg
    = UrlClicked Browser.UrlRequest
    | UrlChanged Url.Url
    | Online Bool
    | ReplaceUrl String
    | NoOpFrontendMsg


type ToBackend
    = NoOpToBackend


type BackendMsg
    = NoOpBackendMsg


type ToFrontend
    = NoOpToFrontend
