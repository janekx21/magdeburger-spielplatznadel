module Types exposing (..)

import Browser exposing (UrlRequest)
import Browser.Navigation as Nav
import Url exposing (Url)


type alias FrontendModel =
    { key : Nav.Key
    , route : Route
    , oldRoute : Maybe Route
    , capture : String
    , message : String
    , online : Bool
    }


type Route
    = MainRoute
    | PlaygroundRoute String
    | AwardsRoute


type alias BackendModel =
    { message : String
    }


type FrontendMsg
    = UrlClicked UrlRequest
    | UrlChanged Url
    | Capture String
    | CreateCapture
    | Online Bool
    | NoOpFrontendMsg


type ToBackend
    = NoOpToBackend


type BackendMsg
    = NoOpBackendMsg


type ToFrontend
    = NoOpToFrontend
