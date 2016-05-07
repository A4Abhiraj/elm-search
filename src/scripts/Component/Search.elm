module Component.Search exposing (..)

-- where

import Dict
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Http
import Json.Decode as Json
import Set
import String
import Task
import Component.PackageDocs as PDocs
import Docs.Summary as Summary
import Docs.Entry as Entry
import Docs.Name as Name
import Docs.Package as Docs
import Docs.Type as Type
import Docs.Version as Version
import Page.Context as Ctx
import Utils.Path exposing ((</>))
import Logo


-- MODEL


type Model
  = Loading
  | Failed Http.Error
  | Catalog (List Summary.Summary)
  | Docs Info


type alias Info =
  { packageDict : Packages
  , chunks : List Chunk
  , failed : List Summary.Summary
  , query : String
  }


type alias PackageIdentifier =
  String


type alias Packages =
  Dict.Dict PackageIdentifier PackageInfo


type alias PackageInfo =
  { package : Docs.Package
  , context : Ctx.VersionContext
  , nameDict : Name.Dictionary
  }


type alias Chunk =
  { package : PackageIdentifier
  , name : Name.Canonical
  , entry : Entry.Model Type.Type
  , entryNormalized : Entry.Model Type.Type
  }



-- INIT


init : ( Model, Cmd Msg )
init =
  ( Loading
  , getPackageInfo
  )



-- UPDATE


type Msg
  = Fail Http.Error
  | Load ( List Summary.Summary, List String )
  | FailDocs Summary.Summary
  | RequestDocs Summary.Summary
  | MakeDocs Ctx.VersionContext Docs.Package
  | Query String


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
  case msg of
    Query query ->
      flip (,) Cmd.none
        <| case model of
            Docs info ->
              Docs { info | query = query }

            _ ->
              model

    Fail httpError ->
      ( Failed httpError
      , Cmd.none
      )

    Load ( allSummaries, updatedPkgs ) ->
      let
        updatedSet =
          Set.fromList updatedPkgs

        ( summaries, oldSummaries ) =
          List.partition (\{ name } -> Set.member name updatedSet) allSummaries

        loadEffects =
          List.map getDocs summaries
      in
        ( Catalog summaries
        , Cmd.batch loadEffects
        )

    FailDocs summary ->
      case model of
        Docs info ->
          ( Docs { info | failed = summary :: info.failed }
          , Cmd.none
          )

        _ ->
          ( Docs (Info (Dict.empty) [] [ summary ] "")
          , Cmd.none
          )

    RequestDocs summary ->
      ( model
      , getDocs summary
      )

    MakeDocs ctx docs ->
      let
        { user, project, version } =
          ctx

        pkgName =
          user </> project </> version

        pkgInfo =
          PackageInfo docs ctx (PDocs.toNameDict docs)

        chunks =
          docs
            |> Dict.toList
            |> List.concatMap (\( name, moduleDocs ) -> toChunks pkgName moduleDocs)
      in
        case model of
          Docs info ->
            ( Docs
                { info
                  | packageDict = Dict.insert pkgName pkgInfo info.packageDict
                  , chunks = List.append info.chunks chunks
                }
            , Cmd.none
            )

          _ ->
            ( Docs (Info (Dict.singleton pkgName pkgInfo) chunks [] "")
            , Cmd.none
            )


latestVersionContext : Summary.Summary -> Result String Ctx.VersionContext
latestVersionContext summary =
  let
    userProjectList =
      List.take 2 (String.split "/" summary.name)

    latestVersionSingleton =
      summary.versions
        |> List.take 1
        |> List.map Version.vsnToString
  in
    case List.append userProjectList latestVersionSingleton of
      [ user, project, version ] ->
        Result.Ok
          (Ctx.VersionContext user project version [] Nothing)

      _ ->
        Result.Err
          "Summary is corrupted"



-- EFFECTS


getPackageInfo : Cmd Msg
getPackageInfo =
  let
    getAll =
      Http.get Summary.decoder "/all-packages.json"

    getNew =
      Http.get (Json.list Json.string) "/new-packages.json"
  in
    Task.perform Fail Load (Task.map2 (,) getAll getNew)


getDocs : Summary.Summary -> Cmd Msg
getDocs summary =
  let
    contextResult =
      latestVersionContext summary

    onFail =
      \_ -> FailDocs summary
  in
    case contextResult of
      Result.Ok context ->
        Ctx.getDocs context
          |> Task.perform onFail (MakeDocs context)

      Result.Err error ->
        Task.fail error
          |> Task.perform onFail onFail



-- VIEW


view : Model -> Html Msg
view model =
  div
    [ class "searchApp" ]
    --<| (viewLogo model)
    --::
    <|
      case model of
        Loading ->
          [ p [] [ text "Loading list of packages..." ] ]

        Failed httpError ->
          [ p [] [ text "Package summary did not load." ]
          , p [] [ text (toString httpError) ]
          ]

        Catalog catalog ->
          [ p [] [ text <| "Loading docs for " ++ toString (List.length catalog) ++ "packages..." ]
          ]

        Docs info ->
          [ viewSearchInput info
          , if String.isEmpty info.query then
              viewSearchIntro info
            else
              viewSearchResults info
          ]


viewLogo : Model -> Html msg
viewLogo model =
  div
    [ class "logo"
    , style
        [ ( "padding", "64px 0 32px 0" )
        , ( "text-align", "center" )
        ]
    ]
    [ Logo.view ]


viewSearchInput : Info -> Html Msg
viewSearchInput info =
  div
    [ class "searchSearchInput" ]
    [ input
        [ placeholder "Search function by name or type signature"
          --, value info.query
        , onInput Query
        ]
        []
    , (if info.query == "" then
        text ""
       else
        button [ onClick (Query "") ] [ text "×" ]
      )
    ]


viewSearchIntro : Info -> Html Msg
viewSearchIntro info =
  div
    []
    [ h1 [] [ text "Welcome to the Elm API Search" ]
    , p [] [ text "Search the modules of the latest Elm packages by either function name or by approximate type signature." ]
    , h2 [] [ text "Example searches" ]
    , exampleSearches
    , viewPackesInfo info
    ]


exampleSearches : Html Msg
exampleSearches =
  let
    exampleQueries =
      [ "map"
      , "(a -> b -> b) -> b -> List a -> b"
      , "Result x a -> (a -> Result x b) -> Result x b"
      , "(x -> y -> z) -> y -> x -> z"
      ]

    exampleSearchItem query =
      li
        []
        [ a
            [ style [ ( "cursor", "pointer" ) ]
            , onClick (Query query)
            ]
            [ code [] [ text query ] ]
        ]
  in
    ul [] (List.map exampleSearchItem exampleQueries)


viewPackesInfo : Info -> Html Msg
viewPackesInfo info =
  div
    []
    [ h2 [] [ text "Some statistics" ]
    , p
        []
        [ text "The search index contains "
        , strong [] [ text (toString (Dict.size info.packageDict)) ]
        , text " packages with a total of "
        , strong [] [ text (toString (List.length info.chunks)) ]
        , text " type definitions."
        ]
    , if not (List.isEmpty info.failed) then
        div
          []
          [ p [] [ text "The following packages did not load or parse," ]
          , ul
              []
              (List.map
                (\summary ->
                  li
                    []
                    [ a
                        [ href ("http://package.elm-lang.org/packages/" ++ summary.name)
                        , style [ ( "color", "#bbb" ) ]
                        ]
                        [ text summary.name ]
                    ]
                )
                info.failed
              )
          ]
      else
        text ""
    ]


viewSearchResults : Info -> Html Msg
viewSearchResults ({ query, chunks } as info) =
  let
    queryType =
      Type.normalize (PDocs.stringToType query)

    filteredChunks =
      case queryType of
        Type.Var string ->
          chunks
            |> List.map (\chunk -> ( Entry.nameDistance query chunk.entry, chunk ))
            |> List.filter (\( distance, _ ) -> distance <= Type.lowPenalty)

        _ ->
          chunks
            |> List.map (\chunk -> ( Entry.typeDistance queryType chunk.entryNormalized, chunk ))
            |> List.filter (\( distance, _ ) -> distance <= Type.lowPenalty)
  in
    if List.length filteredChunks == 0 then
      div
        []
        [ p [] [ text "Your search did not yield any results. You can try one of the examples below." ]
        , exampleSearches
        ]
    else
      div [] (searchResultsChunks info filteredChunks)


searchResultsChunks : Info -> List ( comparable, Chunk ) -> List (Html msg)
searchResultsChunks { packageDict } weightedChunks =
  weightedChunks
    |> List.sortBy (\( distance, _ ) -> distance)
    |> List.map
        (\( distance, { package, name, entry } ) ->
          div
            []
            [ Entry.typeViewSearch package name (nameDict packageDict package) entry
              --, div [ class "searchDebug" ] [ text (toString distance) ]
            ]
        )



-- MAKE CHUNKS


toChunks : PackageIdentifier -> Docs.Module -> List Chunk
toChunks pkgIdent moduleDocs =
  case String.split "\n@docs " moduleDocs.comment of
    [] ->
      []

    firstChunk :: rest ->
      List.concatMap (subChunks pkgIdent moduleDocs) rest


subChunks : PackageIdentifier -> Docs.Module -> String -> List Chunk
subChunks pkgIdent moduleDocs postDocs =
  catMaybes (subChunksHelp pkgIdent moduleDocs (String.split "," postDocs))


subChunksHelp : PackageIdentifier -> Docs.Module -> List String -> List (Maybe Chunk)
subChunksHelp pkgIdent moduleDocs parts =
  case parts of
    [] ->
      []

    rawPart :: remainingParts ->
      let
        part =
          String.trim rawPart
      in
        case PDocs.isValue part of
          Just valueName ->
            toMaybeChunk pkgIdent moduleDocs valueName
              :: subChunksHelp pkgIdent moduleDocs remainingParts

          Nothing ->
            let
              trimmedPart =
                String.trimLeft rawPart
            in
              case String.words trimmedPart of
                [] ->
                  []

                token :: _ ->
                  case PDocs.isValue token of
                    Just valueName ->
                      [ toMaybeChunk pkgIdent moduleDocs valueName ]

                    Nothing ->
                      []


toMaybeChunk : PackageIdentifier -> Docs.Module -> String -> Maybe Chunk
toMaybeChunk pkgIdent moduleDocs name =
  case Dict.get name moduleDocs.entries of
    Nothing ->
      Nothing

    Just e ->
      let
        entry =
          Entry.map PDocs.stringToType e

        entryNormalized =
          Entry.map Type.normalize entry
      in
        Just
          <| Chunk
              pkgIdent
              (Name.Canonical moduleDocs.name name)
              entry
              entryNormalized


nameDict : Packages -> PackageIdentifier -> Name.Dictionary
nameDict packageDict name =
  case Dict.get name packageDict of
    Just info ->
      .nameDict info

    Nothing ->
      Dict.empty


chunkPackage : Packages -> PackageIdentifier -> Docs.Package
chunkPackage packageDict name =
  case Dict.get name packageDict of
    Just info ->
      .package info

    Nothing ->
      Dict.empty


catMaybes : List (Maybe a) -> List a
catMaybes xs =
  case xs of
    [] ->
      []

    Nothing :: xs' ->
      catMaybes xs'

    (Just x) :: xs' ->
      x :: catMaybes xs'
