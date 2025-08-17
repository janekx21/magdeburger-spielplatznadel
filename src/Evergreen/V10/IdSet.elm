module Evergreen.V10.IdSet exposing (..)

import Dict


type alias Guid =
    String


type IdSet a
    = IdSet (Dict.Dict Guid a)
