module Ui.Builder exposing (parentMap, propertyMap, toTree)

import Contracts exposing (Contract, ContractProperties, PropertyID, Property, fetch, Type, TypeDescr(..))
import Dict exposing (Dict)
import Ui.MetaData exposing (..)
import Ui.Tree exposing (..)
import Ui.Widgets.Function
import Ui.Widgets.Button
import Ui.Widgets.Slider
import Ui.Widgets.Switch
import Ui.Widgets.Choice
import Ui.Widgets.List
import Ui.Widgets.Text


toTree : Contract -> ContractProperties -> ( WidgetID, Widgets )
toTree contract properties =
    toTree_ contract "root" properties noWidgets


toTree_ : Contract -> String -> ContractProperties -> Widgets -> ( WidgetID, Widgets )
toTree_ c key properties widgets =
    let
        metaMaker =
            getMetaData key c
    in
    let
        metaData =
            metaMaker properties
    in
    case c of
        Contracts.Constant val subcontract ->
            let
                widget = case val of
                    Contracts.SimpleString s ->
                        StringWidget metaData <| Contracts.SimpleString s

                    Contracts.SimpleInt x ->
                        NumberWidget metaData <| Contracts.SimpleInt x

                    Contracts.SimpleFloat x ->
                        NumberWidget metaData <| Contracts.SimpleFloat x

                    Contracts.SimpleBool x -> SwitchWidget <|
                        Ui.Widgets.Switch.init metaData <| Contracts.SimpleBool x

                    _ -> StringWidget metaData <| Contracts.SimpleString "<const>"
            in let
                ( children, newWidgets ) =
                    Dict.toList subcontract
                        |> toTreeMany properties widgets
            in
                simpleTree newWidgets
                    key
                    metaMaker
                    children
                    widget

        Contracts.Function ({ argument, retval } as callee) subcontract ->
            let
                widget = case (argument.t, retval.t) of
                    (TNil, TLiteral _) ->
                        ButtonWidget <| Ui.Widgets.Button.init metaData callee
                    (TNil, TNil) ->
                        ButtonWidget <| Ui.Widgets.Button.init metaData callee
                    (TNil, TVoid) ->
                        ButtonWidget <| Ui.Widgets.Button.init metaData callee
                    _ ->
                        (FunctionWidget <| Ui.Widgets.Function.init metaData callee)
            in let
                ( children, newWidgets ) =
                    Dict.toList subcontract
                        |> toTreeMany properties widgets
            in
                simpleTree newWidgets
                    key
                    metaMaker
                    children
                    widget

        Contracts.MapContract d ->
            let
                ( children, newWidgets ) =
                    Dict.toList d
                        |> toTreeMany properties widgets
            in
            simpleTree newWidgets key metaMaker children (ListWidget <| Ui.Widgets.List.init metaData)

        Contracts.PropertyKey property d ->
            let
                ( children, newWidgets ) =
                    Dict.toList d
                        |> toTreeMany properties widgets
            in let
                node =
                    { key = key
                    , metaMaker = metaMaker
                    , children = children
                    }
                propval = Maybe.withDefault Contracts.Loading <|
                    Dict.get property.path properties
            in
                addWidget ( propertyWidget property propval metaData, node ) newWidgets


toTreeMany : ContractProperties -> Widgets -> List ( String, Contract ) -> ( List WidgetID, Widgets )
toTreeMany properties initialWidgets l =
    List.foldr
        (\( key, c ) ( trees, widgets ) -> toTree_ c key properties widgets |> (\( t, w ) -> ( t :: trees, w )))
        ( [], initialWidgets )
        l


propertyWidget : Contracts.Property -> Contracts.Value -> MetaData -> Widget
propertyWidget prop value metaData =
    case prop.propertyType.t of
        Contracts.TFloat ->
            case (metaData.valueMeta.min, metaData.valueMeta.max) of
                (Just _, Just _) ->
                    SliderWidget <| Ui.Widgets.Slider.init metaData value

                _ ->
                    NumberWidget metaData value

        Contracts.TInt ->
            NumberWidget metaData value

        Contracts.TString -> case metaData.valueMeta.oneOf of
            Nothing ->
                case hasSetter metaData of
                    False ->
                        StringWidget metaData value
                    True ->
                        TextWidget <|
                            Ui.Widgets.Text.init metaData Nothing
            Just _ ->
                case hasSetter metaData of
                    False ->
                        StringWidget metaData value
                    True ->
                        ChoiceWidget <|
                            Ui.Widgets.Choice.init metaData Nothing

        Contracts.TBool -> SwitchWidget <|
            Ui.Widgets.Switch.init metaData value

        unk ->
            UnknownWidget prop.propertyType metaData value


propertyMap : ContractProperties -> Widgets -> Dict PropertyID WidgetID
propertyMap properties ( w, _ ) =
    w
        |> Dict.toList
        |> List.map (\( id, ( _, { metaMaker } ) ) -> ( metaMaker properties, id ))
        |> List.map (\( meta, id ) -> case meta.property of
            Just prop -> [( prop.path, id )]
            Nothing   -> []
            )
        |> List.concat
        |> Dict.fromList


parentMap : ContractProperties -> Widgets -> Dict PropertyID WidgetID
parentMap properties ( w, l ) =
    w
        |> Dict.toList
        |> List.concatMap (\( id, ( _, { children } ) ) -> List.map (\child -> ( child, id )) children)
        |> List.map (\( child, id ) -> ( getWidget child ( w, l ), id ))
        |> List.map (\( ( _, { metaMaker } ), id ) -> ( metaMaker properties, id ))
        |> List.map (\( meta, id ) -> case meta.property of
            Just prop -> [( prop.path, id )]
            Nothing   -> []
            )
        |> List.concat
        |> Dict.fromList
