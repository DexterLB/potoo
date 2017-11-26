module Contracts exposing (..)
import Dict exposing (Dict)

import Json.Decode exposing (Decoder, decodeString, string, int, float, oneOf, andThen, field, fail, dict, null, succeed)
import Json.Encode

import Result

type alias Data = Dict String String

type Type
  = TNil
  | TInt
  | TFloat
  | TAtom
  | TString
  | TBool
  | TLiteral String
  | TType Type Data
  | TDelegate
  | TChannel Type
  | TUnion Type Type
  | TList Type
  | TMap Type Type
  | TTuple (List Type)
  | TStruct (Dict String Type)
  | TUnknown String

type Contract
  = StringValue String
  | IntValue Int
  | FloatValue Float
  | Delegate {
    destination : Int,
    data: Data
  }
  | Function {
    argument: Type,
    name: String,
    retval: Type,
    data: Data
  }
  | MapContract (Dict String Contract)
  | ListContract (List Contract)

type VisualContract
  = VStringValue String
  | VIntValue Int
  | VFloatValue Float
  | VConnectedDelegate {
    contract: VisualContract,
    destination: Int,
    data: Data
  }
  | VBrokenDelegate {
    destination: Int,
    data: Data
  }
  | VFunction {
    argument: Type,
    name: String,
    retval: Type,
    data: Data,
    pid: Int
  }
  | VMapContract (Dict String VisualContract)
  | VListContract (List VisualContract)

parseContract : String -> Result String Contract
parseContract s = decodeString contractDecoder s

parseType : String -> Result String Type
parseType s = decodeString typeDecoder s

contractDecoder : Decoder Contract
contractDecoder = oneOf [
    stringValueDecoder,
    intValueDecoder,
    floatValueDecoder,
    objectDecoder,
    Json.Decode.lazy (\_ -> mapDecoder),
    Json.Decode.lazy (\_ -> listDecoder)
  ]

stringValueDecoder : Decoder Contract
stringValueDecoder = Json.Decode.map StringValue string

intValueDecoder : Decoder Contract
intValueDecoder = Json.Decode.map IntValue int

floatValueDecoder : Decoder Contract
floatValueDecoder = Json.Decode.map FloatValue float

objectDecoder : Decoder Contract
objectDecoder = field "__type__" string
  |> andThen (\t -> case t of
    "delegate" -> delegateDecoder
    "function" -> functionDecoder
    _ -> fail <| "object type `" ++ t ++ "' is unknown")

delegateDecoder : Decoder Contract
delegateDecoder = Json.Decode.map2 makeDelegate 
  (field "destination" int)
  (field "data" dataDecoder)

functionDecoder : Decoder Contract
functionDecoder = Json.Decode.map4 makeFunction
  (field "argument" typeDecoder)
  (field "name" string)
  (field "retval" typeDecoder)
  (field "data" dataDecoder)

mapDecoder : Decoder Contract
mapDecoder = Json.Decode.map MapContract <|
  dict (Json.Decode.lazy (\_ -> contractDecoder))

listDecoder : Decoder Contract
listDecoder = Json.Decode.map ListContract <|
  Json.Decode.list (Json.Decode.lazy (\_ -> contractDecoder))

dataDecoder : Decoder Data
dataDecoder = dict string

makeDelegate : Int -> Data -> Contract
makeDelegate destination data = Delegate {
    destination = destination,
    data = data
  }

makeFunction : Type -> String -> Type -> Data -> Contract
makeFunction argument name retval data = Function {
    argument = argument,
    name = name,
    retval = retval,
    data = data
  }

typeDecoder : Decoder Type
typeDecoder = oneOf [
    recursiveTypeDecoder,
    tUnknownDecoder
  ]

recursiveTypeDecoder : Decoder Type
recursiveTypeDecoder = Json.Decode.lazy <| \_ -> oneOf [
    tNilDecoder,
    tSimpleDecoder,
    Json.Decode.lazy <| \_ -> tComplexDecoder
  ]

tNilDecoder : Decoder Type
tNilDecoder = (null TNil)

tSimpleDecoder : Decoder Type
tSimpleDecoder = string
  |> andThen (\t -> case t of
    "int" -> succeed TInt
    "bool" -> succeed TBool
    "float" -> succeed TFloat
    "string" -> succeed TString
    "atom" -> succeed TAtom
    "delegate" -> succeed TDelegate
    _ -> fail <| "type '" ++ t ++ "' is not simple")

tComplexDecoder : Decoder Type
tComplexDecoder = Json.Decode.index 0 string
  |> andThen (\t -> case t of
    "struct"  -> oneOf [tStructDecoder, tTupleDecoder]
    "map"     -> tBinaryDecoder TMap
    "list"    -> tUnaryDecoder  TList
    "union"   -> tBinaryDecoder TUnion
    "channel" -> tUnaryDecoder  TChannel
    "type"    -> tTaggedTypeDecoder
    "literal" -> tLiteralDecoder
    _ -> fail <| "complex type '" ++ t ++ "' is unknown"
  )

tStructDecoder : Decoder Type
tStructDecoder = Json.Decode.index 1 <| Json.Decode.map TStruct <|
  Json.Decode.dict recursiveTypeDecoder

tTupleDecoder : Decoder Type
tTupleDecoder = Json.Decode.index 1 <| Json.Decode.map TTuple <|
  Json.Decode.list recursiveTypeDecoder

tUnaryDecoder : (Type -> Type) -> Decoder Type
tUnaryDecoder f = Json.Decode.map f
  (Json.Decode.index 1 recursiveTypeDecoder)

tBinaryDecoder : (Type -> Type -> Type) -> Decoder Type
tBinaryDecoder f = Json.Decode.map2 f
  (Json.Decode.index 1 recursiveTypeDecoder)
  (Json.Decode.index 2 recursiveTypeDecoder)

tTaggedTypeDecoder : Decoder Type
tTaggedTypeDecoder = Json.Decode.map2 TType
  (Json.Decode.index 1 recursiveTypeDecoder)
  (Json.Decode.index 2 dataDecoder)

tLiteralDecoder : Decoder Type
tLiteralDecoder = Json.Decode.map TLiteral
  (Json.Decode.index 1 <|
    Json.Decode.map (\v -> Json.Encode.encode 0 v) Json.Decode.value
  )


tUnknownDecoder : Decoder Type
tUnknownDecoder = Json.Decode.map 
  (\v -> TUnknown <| Json.Encode.encode 4 v)
  Json.Decode.value

toVisual : Int -> Dict Int Contract -> VisualContract
toVisual pid contracts = case Dict.get pid contracts of
  (Just contract) -> toVisual_ contract pid contracts
  Nothing -> VBrokenDelegate {
      destination = pid,
      data = Dict.fromList []
    }

toVisual_ : Contract -> Int -> Dict Int Contract -> VisualContract
toVisual_ c pid contracts = case c of 
  StringValue s -> VStringValue s
  IntValue i -> VIntValue i
  FloatValue f -> VFloatValue f
  Function {argument, name, retval, data}
    -> VFunction {
        argument = argument,
        name = name,
        retval = retval,
        data = data,
        pid = pid
      }
  Delegate {destination, data}
    -> case Dict.get destination contracts of
      (Just contract) -> VConnectedDelegate {
        contract = toVisual_ contract destination contracts,
        data = data,
        destination = destination
      }
      Nothing -> VBrokenDelegate {
        data = data,
        destination = destination
      }
  MapContract d
    -> Dict.map (\_ contract -> toVisual_ contract pid contracts) d
      |> VMapContract
  ListContract l
    -> List.map (\contract -> toVisual_ contract pid contracts) l
      |> VListContract

inspectType : Type -> String
inspectType t = case t of
  TStruct d -> d 
    |> Dict.toList 
    |> List.map (\(k, v) -> k ++ ": " ++ (inspectType v))
    |> String.join ", "
    |> (\s -> "{ " ++ s ++ " }")
  TTuple l -> l
    |> List.map inspectType
    |> String.join(", ")
    |> (\s -> "( " ++ s ++ " )")

  TUnion a b -> "(" ++ (inspectType a) ++ " | " ++ (inspectType b) ++ ")"
  TType t d -> (inspectType t) ++ inspectData d
  TLiteral json -> json
  TChannel t -> "channel[" ++ (inspectType t) ++ "]"
  TList t -> "list[" ++ (inspectType t) ++ "]"
  TMap k v -> "map[" ++ (inspectType k) ++ " → " ++ (inspectType v) ++ "]"

  TInt -> "int"
  TFloat -> "float"
  TString -> "string"
  TBool -> "bool"
  TAtom -> "atom"
  TDelegate -> "delegate"
  TNil -> "nil"

  _ -> toString t

inspectData : Data -> String
inspectData d = d
  |> Dict.toList
  |> List.map (\(k, v) -> k ++ ": " ++ v)
  |> String.join ", "
  |> (\s -> "<" ++ s ++ ">")