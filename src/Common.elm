module Common exposing (..)

import Dict
import IdSet exposing (IdSet)
import Types exposing (Award, Guid, Playground, Role(..), User, UserId)


allAwards : IdSet Playground -> List Award
allAwards playgrounds =
    playgrounds |> IdSet.toList |> List.concatMap .awards


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


removeItemViaId : { a | id : Guid } -> List { a | id : Guid } -> List { a | id : Guid }
removeItemViaId item list =
    list
        |> List.map (\p -> ( p.id, p ))
        |> Dict.fromList
        |> Dict.remove item.id
        |> Dict.values


replaceInList : List a -> Int -> a -> List a
replaceInList list index a =
    list
        |> List.indexedMap (\i x -> ( i, x ))
        |> Dict.fromList
        |> Dict.insert index a
        |> Dict.values


removeInList : List a -> Int -> List a
removeInList list index =
    list
        |> List.indexedMap (\i x -> ( i, x ))
        |> Dict.fromList
        |> Dict.remove index
        |> Dict.values


getItemInList : List a -> Int -> Maybe a
getItemInList list index =
    list
        |> List.indexedMap (\i x -> ( i, x ))
        |> Dict.fromList
        |> Dict.get index


defaultMarkerIcon =
    { url = "/assets/images/playground_icon_1.png", shadowUrl = "/assets/images/playground_icon_1_shadow.png" }


initEmptyUser : UserId -> User
initEmptyUser id =
    { id = id, awards = IdSet.empty, role = RegularUser }


userCanRole : Role -> User -> Bool
userCanRole role user =
    roleCan user.role role


roleCan : Role -> Role -> Bool
roleCan role check =
    let
        allRoles =
            role :: roleInherits role
    in
    allRoles |> List.any (\r -> r == check)


roleInherits : Role -> List Role
roleInherits role =
    case role of
        RegularUser ->
            []

        Moderator ->
            [ RegularUser ]

        Admin ->
            [ RegularUser, Moderator ]
