module Ui.Action exposing (Action(..), ActionResult(..))

import Contracts exposing (Callee, Property)
import Json.Encode as JE

type Action
    = RequestCall Callee JE.Value String
    | RequestSet  Property JE.Value

type ActionResult
    = CallResult JE.Value String
