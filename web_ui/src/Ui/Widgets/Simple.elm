module Ui.Widgets.Simple exposing (..)

import Ui.MetaData exposing (MetaData, noMetaData, uiTagsToStrings, uiLevel, getFloatTag, getStringTag, getIntTag)
import Html exposing (Html, div, text, Attribute, span)
import Html.Attributes exposing (class, style)
import Round exposing (round)

type alias Attributes msg = List (Attribute msg)

renderHeaderExtra : Attributes msg -> MetaData -> List (Html msg) -> List (Html msg) -> Html msg
renderHeaderExtra attrs meta body extra =
    div (metaAttributes meta ++ attrs) (
        [ div [ class "body"   ] ((div [ class "header" ] [ text <| label meta]) :: body)
        ] ++ extra)

metaAttributes : MetaData -> Attributes msg
metaAttributes ({ key, description, uiTags, enabled } as meta)=
    let
        level = if uiLevel meta >= 1.0 then "advanced" else "basic"
    in
        [ class "widget"
        , class ("level-" ++ level)
        , boolClass "enabled" enabled
        ]
        ++ (getFloatTag "order" uiTags |> (\order -> case order of
                Just o  -> [ style "order" (String.fromFloat o) ]
                Nothing -> []
            ))
        ++ (List.map (\s -> class <| "ui-" ++ s) <| uiTagsToStrings uiTags)

label : MetaData -> String
label { key, description } = case description of
    ""   -> key
    _    -> description

boolClass : String -> Bool -> Attribute msg
boolClass prefix b = class <| prefix ++ "-" ++ (case b of
    True    -> "yes"
    False   -> "no")

renderHeader : Attributes msg -> MetaData -> List (Html msg) -> Html msg
renderHeader attrs m body = renderHeaderExtra attrs m body []

renderHeaderWithChildren : Attributes msg -> MetaData -> List (Html msg) -> List (Html msg) -> Html msg
renderHeaderWithChildren attrs m children body = renderHeaderExtra attrs m body
    [ renderChildren children ]

renderChildren : List (Html msg) -> Html msg
renderChildren children = div [ class "children" ] (childify children)

childify : List (Html msg) -> List (Html msg)
childify children = children -- do nothing for now

renderStringWidget : MetaData -> String -> List (Html msg) -> Html msg
renderStringWidget m v children = renderHeaderWithChildren [ class "string-value" ] m children <|
    [ text v ]

renderNumberWidget : MetaData -> Float -> List (Html msg) -> Html msg
renderNumberWidget m v children = renderHeaderWithChildren [ class "number-value" ] m children <|
    [ renderNumberValue m v ]

renderNumberValue : MetaData -> Float -> Html msg
renderNumberValue m v = div [ class "value" ] <|
    [ span [ class "value-number" ]
        [ text <| Maybe.withDefault (String.fromFloat v)
               <| Maybe.map (\d -> Round.round d v) <| getIntTag "decimals" m.uiTags ]
    ] ++ (case getStringTag "units" m.uiTags of
        Nothing -> []
        (Just units) -> [ span [ class "value-units", class "units" ] [ text units ] ]
    )

renderBoolWidget : MetaData -> Bool -> List (Html msg) -> Html msg
renderBoolWidget m b children = renderHeaderWithChildren [ class "bool-value" ] m children <|
    [ text (case b of
        True  -> "\u{2714}"
        False -> "\u{274c}"
    ) ]

renderDelegateWidget : MetaData -> Int -> List (Html msg) -> Html msg
renderDelegateWidget m _ children = renderHeader [ class "connected-delegate" ] m <|
    (childify children)

renderBrokenWidget : MetaData -> Int -> Html msg
renderBrokenWidget m _ = renderHeader [ class "broken-delegate" ] m <|
    [ text "not connected" ]

renderUnknownWidget : String -> List (Html msg) -> Html msg
renderUnknownWidget t children = renderHeaderWithChildren
    [ class "unknown-widget" ]
    { noMetaData | key = "unknown_widget" }
    (childify children)
    [ text t ]
