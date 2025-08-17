module Evergreen.V10.Types exposing (..)

import Browser
import Browser.Navigation
import Bytes
import Dict
import Evergreen.V10.Animator
import Evergreen.V10.IdSet
import File
import Http
import Lamdera
import Time
import UUID
import Url


type alias Guid =
    String


type Route
    = MainRoute
    | PlaygroundRoute Guid
    | AwardsRoute
    | NewAwardRoute Guid
    | AdminRoute
    | PlaygroundAdminRoute Guid
    | MyUserRoute
    | LoginRoute Guid


type alias Location =
    { lat : Float
    , lng : Float
    }


type alias Link =
    String


type alias Img =
    { url : Link
    }


type alias Transform =
    { x : Float
    , y : Float
    , rotation : Float
    }


type alias Award =
    { id : Guid
    , title : String
    , image : Img
    , transform : Transform
    }


type alias MarkerIcon =
    { url : String
    , shadowUrl : String
    }


type alias Playground =
    { id : Guid
    , title : String
    , description : String
    , location : Location
    , images : List Img
    , awards : List Award
    , markerIcon : MarkerIcon
    }


type alias GeoLocation =
    { location : Location
    , heading : Maybe Float
    }


type alias Camera =
    { location : Location
    , zoom : Int
    }


type alias UserId =
    Guid


type alias ShareData =
    { files : List String
    , text : String
    , title : String
    , url : String
    }


type ImageTarget
    = PlaygroundImageTarget Playground


type alias ImgurId =
    String


type alias DeleteHash =
    String


type alias ImgurImage =
    { id : ImgurId
    , link : Link
    , deleteHash : DeleteHash
    }


type alias Marker =
    { location : Location
    , icon : MarkerIcon
    , popupText : String
    , opacity : Float
    }


type FrontendMsg
    = UrlClicked Browser.UrlRequest
    | UrlChanged Url.Url
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
    | ImageSelected ImageTarget File.File
    | ImageUploaded ImageTarget (Result Http.Error ImgurImage)
    | ImageDeleted (Result Http.Error ())
    | Tick Time.Posix
    | SnapToLocation
    | CameraMoved Camera
    | MarkerClicked Marker
    | UnfocusPlayground


type Modal
    = ImageModal Img
    | AreYouSureModal String FrontendMsg


type Role
    = RegularUser
    | Moderator
    | Admin


type alias User =
    { id : UserId
    , awards : Evergreen.V10.IdSet.IdSet Award
    , role : Role
    }


type alias FrontendModel =
    { key : Browser.Navigation.Key
    , route : Evergreen.V10.Animator.Timeline Route
    , online : Bool
    , playgrounds : Evergreen.V10.IdSet.IdSet Playground
    , currentGeoLocation : Maybe GeoLocation
    , snapGeoLocation : Bool
    , mapCamera : Camera
    , modal : Maybe Modal
    , seeds : UUID.Seeds
    , user : Maybe User
    , deleteHashes : Dict.Dict Link DeleteHash
    , focusedPlayground : Maybe Playground
    }


type alias Connection =
    { id : Lamdera.ClientId
    , userId : Maybe Guid
    }


type alias BackendModel =
    { playgrounds : Evergreen.V10.IdSet.IdSet Playground
    , connections : Evergreen.V10.IdSet.IdSet Connection
    , users : Evergreen.V10.IdSet.IdSet User
    , deleteHashes : Dict.Dict Link DeleteHash
    }


type ToBackend
    = NoOpToBackend
    | UploadPlayground Playground
    | RemovePlayground Playground
    | Collect Guid
    | SetConnectedUser UserId
    | UploadImage Bytes.Bytes
    | AddDeleteHash Link DeleteHash


type BackendMsg
    = NoOpBackendMsg
    | ClientConnected Lamdera.SessionId Lamdera.ClientId
    | ClientDisconnected Lamdera.ClientId


type ToFrontend
    = NoOpToFrontend
    | PlaygroundUploaded Playground
    | PlaygroundRemoved Playground
    | PlaygroundsFetched (List Playground)
    | UserUpdated User
    | UserLoggedIn
    | DeleteHashUpdated (Dict.Dict Link DeleteHash)
