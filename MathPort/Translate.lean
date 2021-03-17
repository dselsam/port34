/-
Copyright (c) 2020 Microsoft Corporation. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Daniel Selsam
-/
import MathPort.Util
import MathPort.Basic
import MathPort.ActionItem
import MathPort.OldRecursor
import MathPort.Number
import Lean

namespace MathPort
open Lean

-- TODO: put somewhere else or don't call it State
partial def translateName (s : State) (env : Environment) (n : Name) : Name := do
  match s.newNames.find? n with
  | some new => new
  | none     =>
    if n.isStr && n.getString! == "rec" && not n.getPrefix.isAnonymous then
      let newIndName := translateName s env n.getPrefix
      match env.find? newIndName with
      | none => dflt n
      | some cInfo =>
        match cInfo with
        | ConstantInfo.inductInfo _ =>
          if env.contains (mkOldRecName newIndName) then mkOldRecName newIndName
          else newIndName ++ "rec"
        | _ => dflt n
    else dflt n

  where
    dflt n := `Mathlib ++ n

def doubleCheck (e e' : Expr) : MetaM TransformStep := do
  if (← Meta.isDefEq e e') then TransformStep.done e'
  else throwError "[translateNumber] broke def-eq, \n{e}\n\n!=\n\n{e'}"

def translate (e : Expr) : PortM Expr := do
  let s ← get
  let e := e.replaceConstNames (translateName s (← getEnv))
  let e ← liftMetaM $ Meta.transform e (pre := translateNumbers s)
  let e ← liftMetaM $ Meta.transform e (pre := translateAutoParams s)
  e

  where
    translateNumbers s e : MetaM TransformStep :=
      match isConcreteNat? e with
      | some n => TransformStep.done $ mkNatLit n
      | none   =>
        match isNumber? e with
        | none => TransformStep.visit e
        | some info@⟨n, level, type, hasZero?, hasOne?, hasAdd?⟩ =>
          let inst := mkAppN (mkConst `OfNat.mk [level]) #[type, mkNatLit n, e]
          TransformStep.done $ mkAppN (mkConst `OfNat.ofNat [level]) #[type, mkNatLit n, inst]

    translateAutoParams s e : MetaM TransformStep :=
      -- def auto_param : Sort u → name → Sort u :=
      -- λ (α : Sort u) (tac_name : name), α
      if e.isAppOfArity `Mathlib.auto_param 2 then
        let level   := e.getAppFn.constLevels!.head!
        let type    := e.getArg! 0
        let tacName := e.getArg! 1
        -- Note: we currently hardcode `obviously`
        -- if Mathlib really uses other tactics here, we can parse the name from the auto-ported Lean3 string
        let tacSyntax := Syntax.ident SourceInfo.none "obviously".toSubstring `Mathlib.obviously []
        TransformStep.done $ mkAppN (mkConst `autoParam [level]) #[type, obviouslySyntax]
      else
        TransformStep.visit e


end MathPort
