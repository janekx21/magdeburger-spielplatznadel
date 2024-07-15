module IdSet exposing (HasId, IdSet, SeedPair, assignId, empty, fromList, generateId, get, getOrInsert, insert, isEmpty, member, nilId, remove, toList, union)

import Dict exposing (Dict)
import UUID


type alias Guid =
    String


type IdSet a
    = IdSet (Dict Guid a)


type alias HasId a =
    { a | id : Guid }


type alias SeedPair a =
    ( HasId a, UUID.Seeds )


{-| Pass a record with a nil id like UUID.nilString
-}
assignId : SeedPair a -> SeedPair a
assignId ( item, prevSeets ) =
    if UUID.isNilString item.id then
        let
            ( id, nextSeeds ) =
                generateId prevSeets
        in
        ( { item | id = id }, nextSeeds )

    else
        ( item, prevSeets )


nilId : Guid
nilId =
    UUID.nilString


generateId : UUID.Seeds -> ( Guid, UUID.Seeds )
generateId seeds =
    UUID.step seeds
        |> Tuple.mapFirst (UUID.toRepresentation UUID.Compact)


empty : IdSet a
empty =
    IdSet <| Dict.empty


isEmpty : IdSet a -> Bool
isEmpty (IdSet dict) =
    Dict.isEmpty dict


insert : HasId a -> IdSet (HasId a) -> IdSet (HasId a)
insert item (IdSet dict) =
    dict |> Dict.insert item.id item |> IdSet


getOrInsert : Guid -> HasId a -> IdSet (HasId a) -> ( IdSet (HasId a), HasId a )
getOrInsert id item (IdSet dict) =
    case dict |> Dict.get id of
        Just i ->
            ( IdSet dict, i )

        Nothing ->
            ( dict |> Dict.insert item.id item |> IdSet, item )


union : IdSet (HasId a) -> IdSet (HasId a) -> IdSet (HasId a)
union (IdSet a) (IdSet b) =
    Dict.union a b |> IdSet


remove : Guid -> IdSet (HasId a) -> IdSet (HasId a)
remove id (IdSet dict) =
    dict |> Dict.remove id |> IdSet


get : Guid -> IdSet (HasId a) -> Maybe (HasId a)
get guid (IdSet dict) =
    dict |> Dict.get guid


member : HasId a -> IdSet (HasId a) -> Bool
member item (IdSet dict) =
    Dict.member item.id dict


toList : IdSet (HasId a) -> List (HasId a)
toList (IdSet dict) =
    dict |> Dict.values


fromList : List (HasId a) -> IdSet (HasId a)
fromList list =
    list |> List.map (\v -> ( v.id, v )) |> Dict.fromList |> IdSet
