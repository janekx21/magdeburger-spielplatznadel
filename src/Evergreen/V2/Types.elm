module Evergreen.V2.Types exposing (..)

import Browser
import Browser.Navigation
import Url


type Route
    = MainRoute
    | PlaygroundRoute String
    | AwardsRoute
    | NewAwardRoute String


type alias FrontendModel =
    { key : Browser.Navigation.Key
    , route : Route
    , capture : String
    , message : String
    , online : Bool
    }


type alias BackendModel =
    { message : String
    }


type FrontendMsg
    = UrlClicked Browser.UrlRequest
    | UrlChanged Url.Url
    | Capture String
    | CreateCapture
    | Online Bool
    | ReplaceUrl String
    | NoOpFrontendMsg


type ToBackend
    = NoOpToBackend


type BackendMsg
    = NoOpBackendMsg


type ToFrontend
    = NoOpToFrontend
