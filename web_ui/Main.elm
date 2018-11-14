import Html.Styled.Keyed
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css, href, src, styled, class, title)
import Html.Styled.Attributes as Attrs
import Html.Styled.Events exposing (onClick, onInput)
import Navigation
import Navigation exposing (Location)

import UrlParser exposing ((</>), s, string, parseHash)

import Api exposing (..)

import Dict exposing (Dict)
import Set exposing (Set)
import Json.Encode
import Json.Decode
import Random
import Random.String
import Random.Char
import Delay
import Time

import Debug exposing (log)

import Contracts exposing (..)
import Styles

import Modes exposing (..)

import Ui
import Ui.MetaData exposing (..)
import Ui.Action

main =
  Navigation.program
    (\loc -> NewLocation loc)
    { init = init
    , view = view >> toUnstyled
    , update = update
    , subscriptions = subscriptions
    }


-- MODEL

type alias Model =
  { input : String
  , messages : List String
  , conn : Conn
  , mode : Mode
  , location: Location
  , contracts: Dict Int Contract
  , allProperties : Properties
  , fetchingContracts: Set Int
  , toCall : Maybe VisualContract
  , callToken : Maybe String
  , callArgument : Maybe Json.Encode.Value
  , callResult : Maybe Json.Encode.Value

  , ui         : Ui.Model
  }

init : Location -> (Model, Cmd Msg)
init loc =
  (emptyModel loc, startCommand)

startCommand : Cmd Msg
startCommand = Cmd.batch
  [ nextPing
  ]

emptyModel : Location -> Model
emptyModel loc = Model "" [] (connectWithLocation loc) (parseMode loc) loc Dict.empty Dict.empty Set.empty Nothing Nothing Nothing Nothing Ui.blank

parseMode : Location -> Mode
parseMode l = case parseHash (UrlParser.s "mode" </> string) l of
  Just "advanced" -> Advanced
  _               -> Basic

connectWithLocation : Location -> Conn
connectWithLocation { host } = Api.connect ("ws://" ++ host ++ "/ws")


-- UPDATE

type Msg
  = SocketMessage String
  | AskCall VisualContract
  | AskInstantCall VisualContract
  | ActionCall VisualContract
  | CallArgumentInput String
  | PerformCall { target: DelegateStruct, name: String, argument: Json.Encode.Value }
  | PerformCallWithToken { target: DelegateStruct, name: String, argument: Json.Encode.Value } String
  | CancelCall
  | CallGetter (Pid, PropertyID) FunctionStruct
  | CallSetter (Pid, PropertyID) FunctionStruct Json.Encode.Value
  | SendPing
  | NewLocation Location
  | UiMsg Ui.Msg


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    SocketMessage str ->
      case parseResponse str of
        Ok resp -> handleResponse model resp
        Err err -> let msg = "unable to parse response >> " ++ str ++ " << : " ++ err
          in ({model | messages = msg :: model.messages}, Cmd.none)

    AskCall f -> ({model | toCall = Just f, callToken = Nothing, callArgument = Nothing, callResult = Nothing}, Cmd.none)

    AskInstantCall f -> ({model | toCall = Just f, callArgument = Just Json.Encode.null}, instantCall f)

    ActionCall f -> (model, actionCall model f)

    CallArgumentInput input -> ({model | callArgument = checkCallInput input}, Cmd.none)

    PerformCall data -> (model, performCall data)

    PerformCallWithToken data token -> ({model | callToken = Just token}, Api.unsafeCall model.conn data token)

    CancelCall -> ({ model |
        toCall = Nothing,
        callToken = Nothing,
        callArgument = Nothing,
        callResult = Nothing
      }, Cmd.none)

    CallGetter (pid, id) { name } -> (
        model,
        Api.getterCall model.conn
          {target = delegate pid, name = name, argument = Json.Encode.null}
          (pid, id)
      )

    CallSetter (pid, id) { name } value -> (
        model,
        Api.setterCall model.conn
          {target = delegate pid, name = name, argument = value}
          (pid, id)
      )

    SendPing -> (model, sendPing model.conn)

    NewLocation loc -> (emptyModel loc, startCommand)

    UiMsg msg -> let
        (newUi, cmd) = Ui.update handleUiAction UiMsg msg model.ui
      in
        ({ model | ui = newUi }, cmd)

nextPing : Cmd Msg
nextPing = Delay.after 5 Time.second SendPing

handleUiAction : Ui.Action -> Cmd Msg
handleUiAction action = case action of
  Ui.Action.DoNothing -> Cmd.none

instantCall : VisualContract -> Cmd Msg
instantCall vc = case vc of
  (VFunction {argument, name, retval, data, pid}) ->
    performCall {target = delegate pid, name = name, argument = Json.Encode.null}
  _ -> Cmd.none

actionCall : Model -> VisualContract -> Cmd Msg
actionCall model vc = case vc of
  (VFunction {argument, name, retval, data, pid}) ->
    Api.actionCall model.conn {target = delegate pid, name = name, argument = Json.Encode.null}
  _ -> Cmd.none

performCall : {target: DelegateStruct, name: String, argument: Json.Encode.Value} -> Cmd Msg
performCall data = Random.generate
  (PerformCallWithToken data)
  (Random.String.string 64 Random.Char.english)

handleResponse : Model -> Response -> (Model, Cmd Msg)
handleResponse m resp = case resp of
  GotContract pid contract
    -> updateUiCmd <|
      let
        (newContract, properties) = propertify contract
        (newModel, newCommand) = checkMissing newContract {m |
          allProperties = Dict.insert pid properties m.allProperties,
          contracts = Dict.insert pid newContract m.contracts,
          fetchingContracts = Set.remove pid m.fetchingContracts
        }
      in
        (newModel, Cmd.batch [ subscribeProperties m.conn pid properties,
                               newCommand ])

  UnsafeCallResult token value
    -> case m.callToken of
      Just actualToken -> case token of
        actualToken -> ({m | callResult = Just value}, Cmd.none)
      _ -> (m, Cmd.none)
  ValueResult (pid, propertyID) value
    -> (
      { m | allProperties = m.allProperties |>
        Dict.update pid (Maybe.map <|
          Dict.update propertyID (Maybe.map <|
            setValue value
          )
        )
      },
      Cmd.none
    )
  ChannelResult token chan
    -> (m, subscribe m.conn chan token)
  SubscribedChannel token
    -> (Debug.log (Json.Encode.encode 0 token) m, Cmd.none)
  PropertySetterStatus _ status
    -> (Debug.log ("property setter status: " ++ (Json.Encode.encode 0 status)) m, Cmd.none)

  Pong -> (m, nextPing)

  Hello -> (emptyModel m.location, Api.getContract m.conn (delegate 0))


subscribeProperties : Conn -> Pid -> ContractProperties -> Cmd Msg
subscribeProperties conn pid properties
   = Dict.toList properties
  |> List.map (foo conn pid)
  |> Cmd.batch

foo : Conn -> Pid -> (PropertyID, Property) -> Cmd Msg
foo conn pid (id, prop) = case prop.subscriber of
  Nothing -> Cmd.none
  Just { name } -> Cmd.batch
    [ subscriberCall conn
        { target = delegate pid, name = name, argument = Json.Encode.null }
        (pid, id)
    , case prop.getter of
        Nothing -> Cmd.none
        Just { name } -> getterCall conn
          { target = delegate pid, name = name, argument = Json.Encode.null }
          (pid, id)
    ]

setValue : Json.Encode.Value -> Property -> Property
setValue v prop = case decodeValue v prop of
  Ok value -> { prop | value = Just value }
  Err _    -> { prop | value = Just <| Complex v }

decodeValue : Json.Encode.Value -> Property -> Result String Value
decodeValue v prop = case (stripType prop.propertyType) of
    TFloat -> Json.Decode.decodeValue (Json.Decode.float
           |> Json.Decode.map SimpleFloat) v
    TBool  -> Json.Decode.decodeValue (Json.Decode.bool
           |> Json.Decode.map SimpleBool) v
    TInt   -> Json.Decode.decodeValue (Json.Decode.int
           |> Json.Decode.map SimpleInt) v
    TString -> Json.Decode.decodeValue (Json.Decode.string
           |> Json.Decode.map SimpleString) v
    _      -> Err "unknown property type"


checkMissing : Contract -> Model -> (Model, Cmd Msg)
checkMissing c m = let
    missing = Set.diff (delegatePids c |> Set.fromList) m.fetchingContracts
    newModel = {m | fetchingContracts = Set.union m.fetchingContracts missing}
    command = missing |> Set.toList |> List.map delegate |> List.map (Api.getContract m.conn) |> Cmd.batch
  in (newModel, command)

delegatePids : Contract -> List Int
delegatePids contract = case contract of
  (MapContract d)
    -> Dict.values d
    |> List.concatMap delegatePids
  (ListContract l)
    -> l |> List.concatMap delegatePids
  (Delegate {destination})
    -> [destination]
  _ -> []

checkCallInput : String -> Maybe Json.Encode.Value
checkCallInput s = case Json.Decode.decodeString Json.Decode.value s of
  Ok v -> Just v
  _    -> Nothing


updateUi : Model -> Model
updateUi m = { m | ui = Ui.build 0 m.contracts m.allProperties }

updateUiCmd : (Model, a) -> (Model, a)
updateUiCmd (m, x) = (updateUi m, x)

-- SUBSCRIPTIONS

subscriptions : Model -> Sub Msg
subscriptions model =
  Api.listenRaw model.conn SocketMessage


-- VIEW

metaData : VisualContract -> String -> MetaData
metaData vc name = case vc of
  VFunction             {data} -> dataMetaData data
  VConnectedDelegate    {data} -> dataMetaData data
  VBrokenDelegate       {data} -> dataMetaData data
  VMapContract d               -> MetaData
    (Dict.get "ui_level"    d |> Maybe.map valueOf |> Maybe.andThen getIntValue    |> Maybe.withDefault 0)
    (Dict.get "description" d |> Maybe.map valueOf |> Maybe.andThen getStringValue |> Maybe.withDefault name)
    (Dict.get "enabled"     d |> Maybe.map valueOf |> Maybe.andThen getBoolValue  |>  Maybe.withDefault True)
    emptyData
  VStringValue _               -> case isMeta name of
    True  -> MetaData 1 name True emptyData
    False -> MetaData 0 name True emptyData
  VBoolValue _               -> case isMeta name of
    True  -> MetaData 1 name True emptyData
    False -> MetaData 0 name True emptyData
  VIntValue _               -> case isMeta name of
    True  -> MetaData 1 name True emptyData
    False -> MetaData 0 name True emptyData
  VProperty         {contract} -> metaData contract name
  _                            -> MetaData 0 name True emptyData

isMeta : String -> Bool
isMeta s = case s of
  "description" -> True
  "ui_level"    -> True
  "enabled"     -> True
  _             -> False

dataMetaData : Data -> MetaData
dataMetaData d = MetaData
  (  Dict.get "ui_level" d
  |> Maybe.withDefault (Json.Encode.int 0)
  |> Json.Decode.decodeValue Json.Decode.int
  |> Result.withDefault 0)
  (  Dict.get "description" d
  |> Maybe.withDefault (Json.Encode.string "")
  |> Json.Decode.decodeValue Json.Decode.string
  |> Result.withDefault "")
  (  Dict.get "enabled" d
  |> Maybe.withDefault (Json.Encode.bool True)
  |> Json.Decode.decodeValue Json.Decode.bool
  |> Result.withDefault True)
  d


renderContract : Mode -> VisualContract -> Html Msg
renderContract mode vc = div [ Styles.contract mode, Styles.contractContent mode (metaData vc "") ]
  [ renderHeader mode (metaData vc "")
  , renderContractContent mode vc ]

renderContractContent : Mode -> VisualContract -> Html Msg
renderContractContent mode vc = case vc of
  VStringValue s -> div [ Styles.stringValue mode ]
    [text s]
  VIntValue i -> div [ Styles.intValue mode ]
    [text <| toString i]
  VBoolValue i -> div [ Styles.boolValue mode ]
    [text <| toString i]
  VFloatValue f -> div [ Styles.floatValue mode ]
    [text <| toString f]
  VFunction {argument, name, retval, data, pid} -> div [Styles.function mode, title ("name: " ++ name ++ ", pid: " ++ (toString pid))]
    [ div [ Styles.functionArgumentType mode ]
        [ text <| inspectType argument ]
    , div [ Styles.functionRetvalType mode ]
        [ text <| inspectType retval]
    , case argument of
        TNil -> case retval of
          TNil ->
            button [ Styles.actionCallButton mode, onClick (ActionCall vc) ] [ text "button" ]
          _ ->
            button [ Styles.instantCallButton mode, onClick (AskInstantCall vc) ] [ text "instant call" ]
        _ ->
          button [ Styles.functionCallButton mode, onClick (AskCall vc) ] [ text "call" ]
    , renderData mode data
    ]
  VConnectedDelegate {contract, data, destination} -> div [ Styles.connectedDelegate mode ]
    [ div [ Styles.delegateDescriptor mode, title ("destination: " ++ (toString destination))]
        [ renderData mode data ]
    , div [ Styles.delegateSubContract mode ]
        [ renderContract mode contract]
    ]
  VBrokenDelegate {data, destination} -> div [ Styles.brokenDelegate mode ]
    [ div [ Styles.delegateDescriptor mode, title ("destination: " ++ (toString destination))]
        [ renderData mode data ]
    ]
  VMapContract d -> div [ Styles.mapContract mode ] (
    Dict.toList d |> List.map (
      \(name, contract) -> div [ Styles.mapContractItem mode, Styles.contractContent mode (metaData contract name)  ]
        [ renderHeader mode (metaData contract name)
        , div [Styles.mapContractName mode] [ text name ]
        , renderContractContent mode contract
        ]
    ))
  VListContract l -> div [ Styles.listContract mode ] (
    l |> List.map (
      \contract -> div [ Styles.listContractItem mode, Styles.contractContent mode (metaData contract "") ]
        [ renderHeader mode (metaData contract "")
        , renderContractContent mode contract ]
    ))
  VProperty {pid, propertyID, value, contract} -> div [ Styles.propertyBlock mode ]
    [ renderProperty mode pid propertyID value
    , div [ Styles.propertySubContract mode ] [ renderContractContent mode contract ]
    ]

renderHeader : Mode -> MetaData -> Html Msg
renderHeader mode { description, enabled } = div [ Styles.contractHeader mode enabled ]
  [ text description ]

renderData : Mode -> Data -> Html Msg
renderData mode d = div [ Styles.dataBlock mode ] (
    Dict.toList d
    |> List.filter (
      \(name, _) -> not <| isMeta name
    )
    |> List.map (
      \(name, value) -> div [ Styles.dataItem mode ]
        [ div [ Styles.dataName mode ] [ text name ]
        , div [ Styles.dataValue mode ] [ text (Json.Encode.encode 0 value) ]
        ]
    ))

renderAskCallWindow : Mode -> Maybe VisualContract -> Maybe Json.Encode.Value -> Maybe String -> Maybe Json.Encode.Value -> Html Msg
renderAskCallWindow mode mf callArgument callToken callResult = case mf of
  Just (VFunction {argument, name, retval, data, pid}) ->
    div [Styles.callWindow mode]
      [ button [onClick CancelCall, Styles.callCancel mode] [text "cancel"]
      , div [Styles.callFunctionName mode]         [text name]
      , div [Styles.callFunctionArgumentType mode] [text <| inspectType argument]
      , div [Styles.callFunctionRetvalType mode]   [text <| inspectType retval]
      , case callArgument of
          Nothing -> div [Styles.callFunctionEntry mode]
            [ input [onInput CallArgumentInput] []
            ]
          Just jsonArg -> case callToken of
            Nothing -> div [Styles.callFunctionEntry mode]
              [ input [onInput CallArgumentInput] []
              , button
                  [ onClick (PerformCall {target = delegate pid, name = name, argument = jsonArg})
                  ] [text "call"]
              ]
            Just _ -> div []
              [ div [Styles.callFunctionInput mode] [text <| Json.Encode.encode 0 jsonArg]
              , case callResult of
                  Nothing -> div [Styles.callFunctionOutputWaiting mode] []
                  Just data -> div [Styles.callFunctionOutput mode] [text <| Json.Encode.encode 0 data]
              ]
      ]

  _ -> div [] []

renderProperty : Mode -> Pid -> PropertyID -> Property -> Html Msg
renderProperty mode pid propID prop = div [Styles.propertyContainer mode] <| justs
  [ renderPropertyControl mode pid propID prop
  , Maybe.map (renderValue mode (propValueStyle mode prop)) prop.value
  , renderPropertyGetButton mode pid propID prop
  ]

propValueStyle : Mode -> Property -> Attribute Msg
propValueStyle mode prop = case prop.setter of
  Nothing -> Styles.readOnlyValue mode
  Just _  -> Styles.propertyValue         mode

renderValue : Mode -> Attribute Msg -> Value -> Html Msg
renderValue mode style v = (case v of
    SimpleInt i -> [ text (toString i) ]
    SimpleString s -> [ text s ]
    SimpleFloat f -> [ text (toString f) ]
    SimpleBool b -> [ text (toString b) ]
    Complex v -> [ text <| Json.Encode.encode 0 v]
  ) |> div [style]

renderPropertyGetButton : Mode -> Pid -> PropertyID -> Property -> Maybe (Html Msg)
renderPropertyGetButton mode pid propID prop = case prop.getter of
  Nothing -> Nothing
  Just getter ->
    Just <| button
      [ onClick (CallGetter (pid, propID) getter), Styles.propertyGet mode ]
      [ text "↺" ]

renderPropertyControl : Mode -> Pid -> PropertyID -> Property -> Maybe (Html Msg)
renderPropertyControl mode pid propID prop = case prop.setter of
  Nothing ->
    case prop.value of
      Just (SimpleFloat value) ->
        case getMinMax prop of
          Just minmax -> Just <| renderFloatBarControl mode pid propID minmax value
          Nothing -> Nothing
      _ -> Nothing
  Just setter ->
    case prop.value of
      Just (SimpleFloat value) ->
        case getMinMax prop of
          Just minmax -> Just <| renderFloatSliderControl mode pid propID minmax setter value
          Nothing -> Nothing
      Just (SimpleBool value) ->
        Just <| renderBoolCheckboxControl mode pid propID setter value
      _ -> Nothing

renderFloatSliderControl : Mode -> Pid -> PropertyID -> (Float, Float) -> FunctionStruct -> Float -> Html Msg
renderFloatSliderControl mode pid propID (min, max) setter value = input
  [ Attrs.type_ "range"
  , Attrs.min (min |> toString)
  , Attrs.max (max |> toString)
  , Attrs.step "0.01"   -- fixme!
  , Attrs.value <| toString value
  , onInput (\s -> s
      |> String.toFloat
      |> Result.withDefault -1
      |> Json.Encode.float
      |> (CallSetter (pid, propID) setter)
    )
  , Styles.propertyFloatSlider
  mode ] []

renderFloatBarControl : Mode -> Pid -> PropertyID -> (Float, Float) -> Float -> Html Msg
renderFloatBarControl mode pid propID (min, max) value
  = let norm = (((value - min) / (max - min))) in
      div [ Styles.propertyFloatBar mode ] [
        div [ Styles.progressBarOuter norm ] [
          div [ Styles.progressBarInner norm ] []
        ]
      ]

renderBoolCheckboxControl : Mode -> Pid -> PropertyID -> FunctionStruct -> Bool -> Html Msg
renderBoolCheckboxControl mode pid propID setter value =
  Html.Styled.Keyed.node "span" [] [
    ((toString value), renderBoolCheckbox mode pid propID setter value)
  ]

renderBoolCheckbox : Mode -> Pid -> PropertyID -> FunctionStruct -> Bool -> Html Msg
renderBoolCheckbox mode pid propID setter value = input
  [ Attrs.type_ "checkbox"
  , Attrs.checked value
  , onClick (CallSetter (pid, propID) setter (Json.Encode.bool <| not value))
  , Styles.propertyBoolCheckbox
  mode ] []

justs : List (Maybe a) -> List a
justs l = case l of
  [] -> []
  (Just h)::t -> h :: (justs t)
  Nothing::t -> justs t

view : Model -> Html Msg
view model =
  div []
    [ renderContract model.mode <| toVisual 0 model.contracts model.allProperties
    , renderAskCallWindow model.mode model.toCall model.callArgument model.callToken model.callResult
    , Html.Styled.map UiMsg <| Html.Styled.fromUnstyled <| Ui.view model.allProperties model.ui
    ]


viewMessage : String -> Html msg
viewMessage msg =
  div [] [ text msg ]
