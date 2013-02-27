{-# LANGUAGE PatternGuards #-}

import Data.Generics
import Data.List
import Language.Haskell.Exts.Annotated
import System.Environment
import System.FilePath
import Text.PrettyPrint

main :: IO ()
main = do
  args <- getArgs
  case args of

    (fn:inp:outp:_) -> do
         contents <- readFile inp
         let res = work fn contents
         writeFile outp res

    [] -> do
         contents <- getContents
         putStrLn $ work "INPUT" contents

    _ -> error "USAGE: MonadLoc expects the input from stdin and writes to stdout"

work :: FilePath -> String -> String
work fn contents =
         -- Invent a fake name for lhs files to avoid confusing haskell-src-exts
         let fn' = if takeExtension fn == ".lhs" then dropExtension fn <.> "hs" else fn

             Module l mhead opt imports decls =
               fromParseResult $
               parseFileContentsWithMode ourParseMode{parseFilename = fn'} contents
             mod'   = Module l mhead opt imports decls'
             mname  = case mhead of
                        Nothing -> ""
                        Just (ModuleHead _ mn _ _) -> prettyPrint mn
             decls' = map (annotateDecl mname) decls
         in prettyPrintStyleMode style{lineLength=100000} ourPrintMode mod'

ourParseMode :: ParseMode
ourParseMode = defaultParseMode { ignoreLinePragmas = False,
                                  extensions =
                                        [CPP
                                        ,MultiParamTypeClasses
                                        ,FunctionalDependencies
                                        ,FlexibleContexts
                                        ,FlexibleInstances
                                        ,ExplicitForAll
                                        ,ExistentialQuantification
                                        ,PatternGuards
                                        ,ViewPatterns
                                        ,Arrows
                                        ,NamedFieldPuns
                                        ,DisambiguateRecordFields
                                        ,RecordWildCards
                                        ,StandaloneDeriving
                                        ,GeneralizedNewtypeDeriving
                                        ,ScopedTypeVariables
                                        ,PatternSignatures
                                        ,PackageImports
                                        ,QuasiQuotes
                                        ,PostfixOperators]
                                }

ourPrintMode :: PPHsMode
ourPrintMode = defaultMode { linePragmas = True }


annotateDecl :: String -> Decl SrcSpanInfo -> Decl SrcSpanInfo
annotateDecl mname e@(FunBind _ (m:_)) = everywhere (mkT (annotateStatements (Just funName) mname)) e
  where
    funName = case m of
              Match _ name _ _ _ -> prettyPrint name
              InfixMatch _ _ name _ _ _ -> prettyPrint name

annotateDecl mname e@(PatBind _ (PVar _ fn) _ _ _) = everywhere (mkT (annotateStatements (Just $ prettyPrint fn) mname)) e
annotateDecl mname e = everywhere (mkT (annotateStatements Nothing mname)) e

annotateStatements :: Maybe String -> String -> Exp SrcSpanInfo -> Exp SrcSpanInfo
annotateStatements fun m (Do loc stmts)  = App loc (withLocCall fun m loc) (Paren loc $ Do  loc $ map (annotateStmt fun m) stmts)
annotateStatements fun m (MDo loc stmts) = App loc (withLocCall fun m loc) (Paren loc $ MDo loc $ map (annotateStmt fun m) stmts)
annotateStatements _   _ e = e

annotateStmt :: Maybe String ->  String -> Stmt SrcSpanInfo -> Stmt SrcSpanInfo
annotateStmt fun m (Generator loc pat exp) = Generator loc pat $ App loc (withLocCall fun m loc) (Paren loc exp)
annotateStmt fun m (Qualifier loc exp)     = Qualifier loc $ App loc (withLocCall fun m loc) (Paren loc exp)
annotateStmt fun m (RecStmt loc stmts)     = RecStmt loc $ map (annotateStmt fun m) stmts
annotateStmt _   _ stmt                    = stmt

withLocCall :: Maybe String -> String -> SrcSpanInfo -> Exp SrcSpanInfo
withLocCall fun m loc = App loc (Var loc withLoc) (Lit loc srclocLit)
  where
   withLoc   = Qual loc (ModuleName loc "Control.Monad.Loc") (Ident loc "withLoc")
   srclocLit = String loc (render locString) ""
   locStringTail = text m <> parens(text (fileName loc)) <> colon <+> parens (int (startLine loc) <> comma <+> int(startColumn loc))
   locString = case fun of
                 Nothing  -> locStringTail
                 Just fun -> text fun <> comma <+> locStringTail

