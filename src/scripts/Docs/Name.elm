module Docs.Name exposing (..)

import Json.Decode as Decode exposing (Decoder)
import String
import Utils.Json


type alias Name =
    { home : String
    , name : String
    }


nameToString : Name -> String
nameToString { home, name } =
    [ home, name ]
        |> List.filter (not << String.isEmpty)
        |> String.join "."


decoder : Decoder Name
decoder =
    Utils.Json.customDecoder Decode.string fromString


fromString : String -> Result String Name
fromString str =
    case List.reverse (String.split "." str) of
        name :: home ->
            Ok (Name (List.reverse home |> String.join ".") name)

        _ ->
            Err (str ++ " is not a valid Elm name")


pathTo : Name -> String
pathTo { home, name } =
    String.map dotToDash
        home
        ++ "#"
        ++ name


dotToDash : Char -> Char
dotToDash char =
    if char == '.' then
        '-'
    else
        char
