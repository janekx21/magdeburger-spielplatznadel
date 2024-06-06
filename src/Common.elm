module Common exposing (..)

import Dict
import Types exposing (Guid)


updateListItemViaId : { a | id : Guid } -> List { a | id : Guid } -> List { a | id : Guid }
updateListItemViaId item list =
    list
        |> List.map (\p -> ( p.id, p ))
        |> Dict.fromList
        |> Dict.insert item.id item
        |> Dict.values


updateListViaId : List { a | id : Guid } -> List { a | id : Guid } -> List { a | id : Guid }
updateListViaId items list =
    let
        newItems =
            items
                |> List.map (\p -> ( p.id, p ))
                |> Dict.fromList
    in
    list
        |> List.map (\p -> ( p.id, p ))
        |> Dict.fromList
        |> Dict.union newItems
        |> Dict.values
