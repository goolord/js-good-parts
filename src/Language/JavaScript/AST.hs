{-# OPTIONS_GHC -Wall #-}
--
-- Module: Language.Javascript.AST
-- Author: Sean Seefried
--
-- © 2012
--
-- In Chapter 2 of "JavaScript: The Good Parts", Douglas Crockford presents a
-- concrete grammar for "the good parts" of JavaScript.
--
-- This module provides an abstract grammar for those good parts. We will abbreviate this
-- language to JS:TGP
--
-- Crockford presents the grammar as a series of railroad diagrams.
-- The correspondence between the concrete grammar and the abstract grammar
-- is NOT one-to-one. However, the following property does hold: the pretty printing
-- of an abstract syntax tree will be parseable by the concrete grammar. i.e.
-- For each valid program produced by the concrete grammar there is a corresponding
-- abstract syntax tree that when pretty printed will produce that program (modulo whitespace).
--
-- The abstract grammar:
--   * removes unnecessary characters such as parentheses (normal, curly and square)
--   * represents JavaScript's string, name and number literals directly in Haskell as
--     'String', 'String' and 'Double' respectively.
--
--
-- Conventions for concrete syntax:
--  -  Non-terminals appear in angle brackets e.g. <JSName>
--  -  ? means zero or one. e.g. <JSExpression>?
--  -  * means zero or more e.g. <JSStatement>*
--  -  + means one  or more e.g. <JSStatement>+
--  -  \( \) are meta-brackets used to enclose a concrete-syntax expression so that ?,* or +
--     can be applied. e.g. \(= <JSExpression>\)*
--     This means zero or more repetitions of: = <JsExpression>
--
-- The data structure ensures no incorrect JS:TGP programs
-- -------------------------------------------------------
-- This library was designed so that it would be impossible, save for name, string literals
-- to construct a JS:TGP program.
--
-- To this end some of the data structures may look like they contain redundancy.
-- For instance, consider the 'JSESDelete' constructor which is defined
--
-- JSESDelete JSExpression JSInvocation
--
-- Why not just define it as 'JSESDelete JSExpression' since type 'JSExpression'
-- has a constructor defined as 'JSExpressionInvocation JSExpression JSInvocation'?
-- The reason is that this would allow incorrect programs. A 'JSExpression' is not necessarily
-- an invocation.
--
--
-- A note on precedence of JavaScript operators
-- --------------------------------------------
-- Although this might be hard to believe, the precedence of JavaScript operators is
-- not defined in the ECMAScript standard. The precedence used in this library comes from
-- the Mozilla Developer's Network pages.
-- (https://developer.mozilla.org/en/JavaScript/Reference/Operators/Operator_Precedence)
--
-- I have not used the precise precedence numbers from that page since in this module
-- a lower precedence means the operator binds more tightly (as opposed to the page where
-- a higher precedence does the same). Also, we have need for less precedence values so they
-- have been normalised to what we are using in JS:TGP
--
-- You will also note that we don't even consider the associativity/precedence of
-- "=", "+=", "-=" etc. In JS:TGP the notion of expression statements is quite different
-- to that of expressions. It simply isn't legal to write an expression statement like
--
--  (a += 2) -= 3
--    OR
--  a = (b = c) = (c = d)
--
-- although it is perfectly legal to write
--
--  a = b = c = d += 2
--
-- which if we add brackets to disambiguate is really
--
-- a = (b = (c = (d += 2)))
--
--
-- Interesting aspects of "the good parts"
-- ---------------------------------------
--
-- A JS:TGP program is a collection of statements. You'll note that there is no
-- statement to declare a function in JS:TGP. However you can assign a function literal
-- to a variable.
--
-- e.g. var fun = function(x) { return x + 1;}
--
-- What about recursive functions then? There is the option to give the function a name which is
-- local to the literal.
--
-- e.g. var factorial = function f(n) {
--                        if ( n > 0 ) {
--                          return n * f(n - 1);
--                        } else {
--                          return 1;
--                        }
--                      }
--
-- 'f' is local i.e. it will not be in scope outside of the function body.
--
module Language.JavaScript.AST (
  -- JSString, JSName can't be create except with constructors
  JSString, JSName, 
  unJSString, unJSName,
  jsString, jsName,
   
  -- Data types
  JSNumber(..),
  JSVarStatement(..), JSVarDecl(..), JSStatement(..),
  JSDisruptiveStatement(..), JSIfStatement(..), JSSwitchStatement(..),
  JSCaseAndDisruptive(..), JSCaseClause(..), JSForStatement(..),
  JSDoStatement(..), JSWhileStatement(..), JSTryStatement(..),
  JSThrowStatement(..), JSReturnStatement(..), JSBreakStatement(..),
  JSExpressionStatement(..), JSLValue(..), JSRValue(..), JSExpression(..),
  JSPrefixOperator(..), JSInfixOperator(..), JSInvocation(..), JSRefinement(..),
  JSLiteral(..), JSObjectLiteral(..), JSObjectField(..), JSArrayLiteral(..),
  JSFunctionLiteral(..), JSFunctionBody(..), JSProgram(..)
) where

import Language.JavaScript.NonEmptyList


data JSName = JSName { unJSName :: String }

--
-- The only way you can create a JSName
--
jsName :: String -> Either String JSName
jsName = Right . JSName -- FIXME: Return Left on error.

data JSString = JSString { unJSString :: String }

--
-- The only way you can create a Javascript string.
-- This function needs to correctly encode all special characters.
-- See p9 of "JavaScript: The Good Parts"
--
jsString :: String -> Either String JSString 
jsString = Right . JSString -- FIXME: Return Left on error


newtype JSNumber = JSNumber Double -- 64 bit floating point number

--
-- Concrete syntax: var <VarDecl> [, <VarDecl>]* ;
--
-- e.g. var x = 1, y;
--
data JSVarStatement = JSVarStatement (NonEmptyList JSVarDecl)

--
-- | Concrete syntax:
--   1. <JSName> \(= <JSExpression>\)?
--
-- e.g.
-- 1. x
-- 2. x = 2 + y
--
data JSVarDecl = JSVarDecl JSName (Maybe JSExpression) -- optional initialization

--
-- | The many different kinds of statements
--
data JSStatement
  = JSStatementExpression   JSExpressionStatement -- ^ syntax: <JSExpressionStatement>;
  | JSStatementDisruptive  JSDisruptiveStatement -- ^ syntax: <JSDisruptiveStatement>
  | JSStatementTry         JSTryStatement        -- ^ syntax: <JSTryStatement>
  | JSStatementIf          JSIfStatement         -- ^ syntax: <JSIfStatement>
  -- | syntax: \(<JSName> : \) <JSSwitchStatement>
  | JSStatementSwitch      (Maybe JSName) JSSwitchStatement
  -- | syntax: \(<JSName> : \) <JSWhileStatement>
  | JSStatementWhile       (Maybe JSName) JSWhileStatement
  -- | syntax: \(<JSName> : \) <JSForStatement>
  | JSStatementFor         (Maybe JSName) JSForStatement
  -- | syntax: \(<JSName> : \) <JSDoStatement>
  | JSStatementDo          (Maybe JSName) JSDoStatement

--
-- | Disruptive statements
--
data JSDisruptiveStatement
  = JSDSBreak   JSBreakStatement  -- syntax: <JSBreakStatement>
  | JSDSReturn  JSReturnStatement -- syntax: <JSReturnStatement>
  | JSDSThrow   JSThrowStatement  -- syntax: <JSThrowStatement>

--
-- | Concrete syntax:
--   if ( <JSExpression> ) { <JSStatement>* }                         -- for 'Nothing'
--     OR
--   if ( <JSExpression> ) { <JSStatement>* } else { <JSStatement>* } -- for 'Just . Left'
--     OR
--   if ( <JSExpression> ) { <JSStatement>* } else <JSIfStatement>    -- for 'Just . Right'
--
--   e.g.
--   if (x > 3) { y = 2; }
--     OR
--   if (x < 2) { y = 1; } else { y = 3; z = 2; }
--     OR
--   if (x > 0) { y = 20; } else if ( x > 10) { y = 30; } else { y = 10; }
--
data JSIfStatement = JSIfStatement JSExpression [JSStatement] (Maybe (Either [JSStatement] JSIfStatement))

--
-- | Concrete syntax:
--   switch ( <Expression> ) { <JSCaseClause> }
--     OR
--   switch ( <Expression> ) { <JSCaseAndDisruptive>+
--                             default : <JSStatement>* }
--   e.g.
--   1. switch ( x ) {
--        case 1:
--          y = 2;
--      }
--   2. switch ( x ) {
--        case 1:
--          y = 2;
--          break;
--        case 2:
--           y = 3;
--           break;
--        default:
--           y = 4;
--      }
--
data JSSwitchStatement
  = JSSwitchStatementSingleCase JSExpression JSCaseClause
  | JSSwitchStatement           JSExpression
                                (NonEmptyList JSCaseAndDisruptive) -- non-default case clauses
                                [JSStatement]                 -- default clause statements

--
-- | A case clause followed by a disruptive statement
--
--   Concrete syntax:
--     <JSCaseClause> <JSDisruptiveStatement>
--   e.g.
--   1. case 2:
--        y = 2;
--        break;
--
data JSCaseAndDisruptive = JSCaseAndDisruptive JSCaseClause JSDisruptiveStatement

--
-- | Concrete syntax:
--   case <JSExpression> : <JSStatement>*
--
--   e.g.
--   1. case 2:   // zero statements following the case expression is valid.
--   2. case 2:
--        y = 1;
--
data JSCaseClause = JSCaseClause JSExpression [JSStatement]

--
-- | Two style of for-statements -- C-style and In-style.
--
--   Concrete syntax:
--
--   1. for (<JSExpressionStatement>? ; <JSExpression>? ; <JSExpressionStatement>? ) {
--        <JSStatement>*
--      }
--   2. for ( <JSName> in <JSExpression> ) {
--        <JSStatement>*
--      }
--
--   e.g.
--   1. for ( ; ; ) { }
--   2. for ( ; x < 10 ;) { x += 1; }
--   3. for (i = 0; i < 10; i += 1) {
--         x += i;
--      }
--   4. for ( i in indices ) { a[i] = 66; }
--
data JSForStatement = JSForStatementCStyle
                        (Maybe JSExpressionStatement) -- initialization
                        (Maybe JSExpression)          -- condition
                        (Maybe JSExpressionStatement) -- increment
                        [JSStatement]                 -- body
                    | JSForStatementInStyle
                        JSName
                        JSExpression
                        [JSStatement]

--
-- | Concrete syntax:
--     do { <JSStatement>* } while ( <JSExpression> );
--
data JSDoStatement = JSDoStatement [JSStatement] JSExpression

--
-- | Concrete syntax:
--     while ( <JSExpression>) { <JSStatement>* }
--
data JSWhileStatement = JSWhileStatement JSExpression [JSStatement]

--
-- | Concrete syntax:
--     try { <JSStatement>* } catch ( <JSName> ) { <JSStatement>* }
--
data JSTryStatement = JSTryStatement [JSStatement] JSName [JSStatement]

--
-- | Concrete syntax:
--     throw <JSExpression>;
--
data JSThrowStatement = JSThrowStatement JSExpression

--
-- | Concrete syntax:
--     return <JSExpression>?;
--   e.g.
--   1. return;
--   2. return 2 + x;
--
data JSReturnStatement = JSReturnStatement (Maybe JSExpression)

--
-- | Concrete syntax:
--     break <JSName>?;
--   e.g.
--   1. break;
--   2. break some_label;
--
data JSBreakStatement = JSBreakStatement (Maybe JSName)

--
-- | Concrete syntax:
--
--

data JSExpressionStatement
  = JSESApply (NonEmptyList JSLValue) JSRValue
  | JSESDelete JSExpression JSRefinement

--
-- | Concrete syntax:
--     <JSName> \(<JSInvocation>* <JSRefinement>\)*
--   e.g.
--   1. x
--   2. x.field_1
--   3. fun().field_1
--   4. fun(1)(2)
--   5. fun(1)(2).field_1
--   5. x.fun_field_1(x+2).fun_field_2(y+3).field_3
--
data JSLValue = JSLValue JSName [([JSInvocation], JSRefinement)]

--
-- | Concrete syntax:
--   1. =  <JSExpression>
--   2. += <JSExpression>
--   3. -= <JSExpression>
--   4. <JSInvocation>+
--
--   e.g.
--   1. = 2
--   2. += 3
--   3. -= (4 + y)
--   4a. ()
--   4b. (1)
--   4c. (x,y,z)
--
data JSRValue
  = JSRVAssign    JSExpression
  | JSRVAddAssign JSExpression
  | JSRVSubAssign JSExpression
  | JSRVInvoke    (NonEmptyList JSInvocation)

data JSExpression = JSExpressionLiteral    JSLiteral
                  | JSExpressionName       JSName
                  | JSExpressionPrefix     JSPrefixOperator JSExpression
                  | JSExpressionInfix      JSInfixOperator  JSExpression JSExpression
                  | JSExpressionTernary    JSExpression     JSExpression JSExpression
                  | JSExpressionInvocation JSExpression     JSInvocation
                  | JSExpressionRefinement JSExpression     JSRefinement
                  | JSExpressionNew        JSExpression     JSInvocation
                  | JSExpressionDelete     JSExpression     JSRefinement

data JSPrefixOperator
  = JSTypeOf   -- syntax: typeof
  | JSToNumber -- syntax: +
  | JSNegate   -- syntax: -
  | JSNot      -- syntax: !

data JSInfixOperator
  = JSMul  -- syntax: *
  | JSDiv  -- syntax: /
  | JSMod  -- syntax: %
  | JSAdd  -- syntax: +
  | JSSub  -- syntax: -
  | JSGTE  -- syntax: >=
  | JSLTE  -- syntax: <=
  | JSGT   -- syntax: >
  | JSLT   -- syntax: <
  | JSEq   -- syntax: ===
  | JSNotEq-- syntax: !==
  | JSOr   -- syntax: ||
  | JSAnd  -- syntax: &&

--
-- | Concrete syntax:
--     <JSExpression>*
--   e.g.
--   1. ()
--   2. (1)
--   3. (x,z,y)
--
data JSInvocation = JSInvocation [JSExpression]

--   e.g.
--   1. .field_1
--   2. [i+1]
--
data JSRefinement
  -- | syntax: .<JSName>
  --   e.g. .field_1
  = JSProperty  JSName
  -- | syntax: [<JSExpression>]
  --   e.g. [x+3]
  | JSSubscript JSExpression

data JSLiteral
  = JSLiteralNumber   JSNumber
  | JSLiteralString   JSString
  | JSLiteralObject   JSObjectLiteral
  | JSLiteralArray    JSArrayLiteral
  | JSLiteralFunction JSFunctionLiteral
--  | JSLiteralRegexp   JSRegexpLiteral -- TODO: Add regexps

--
-- | Concrete syntax:
--   1. {}                                          // no  fields
--   2. {<JSObjectField> \(, <JSObjectField> \)*}   // one or more fields
--
data JSObjectLiteral = JSObjectLiteral [JSObjectField]

--
-- | Concrete syntax:
--   1. <JSName>: <JSExpression>      // for Left
--   2. <JSString>: <JSExpression>     // for Right
--
--   e.g.
--   1. x: y + 3
--   2. "value": 3 - z
--
data JSObjectField  = JSObjectField (Either JSName JSString) JSExpression

--
-- | Concrete syntax:
--   1. []                             // empty array
--   2. [<JSExpression> \(, <JSExpression>*\) ]
--
data JSArrayLiteral = JSArrayLiteral [JSExpression]

--
-- | Concrete syntax:
--   function <JSName>? <JSFunctionBody>
--
data JSFunctionLiteral = JSFunctionLiteral (Maybe JSName) [JSName] JSFunctionBody

--
-- | Concrete syntax:
--   { <JSVarStatement>+ <JSStatement>+ }
--
data JSFunctionBody = JSFunctionBody [JSVarStatement] [JSStatement]

data JSProgram = JSProgram [JSVarStatement] [JSStatement]