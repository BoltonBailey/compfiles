import Std.Data.String.Basic
import Std.Lean.Util.Path
import Std.Tactic.Lint
import Lean.Environment
import Mathlib.Data.String.Defs
import Lean.Meta.Basic

import ProblemExtraction

open Lean Core Elab Command Std.Tactic.Lint

structure ProblemInfo where
  name : String
  solutionUrl : String
  problemUrl : String
  proved : Bool

def htmlEscapeAux (racc : List Char) : List Char → String
| [] => String.mk racc.reverse
| '&'::cs => htmlEscapeAux (("&amp;".data.reverse)++racc) cs
| '<'::cs => htmlEscapeAux (("&lt;".data.reverse)++racc) cs
| '>'::cs => htmlEscapeAux (("&gt;".data.reverse)++racc) cs
| '\"'::cs => htmlEscapeAux (("&quot;".data.reverse)++racc) cs
-- TODO other things that need escaping
-- https://developer.mozilla.org/en-US/docs/Glossary/Entity#reserved_characters
| c::cs => htmlEscapeAux (c::racc) cs

def htmlEscape (s : String) : String :=
  htmlEscapeAux [] s.data

def olean_path_to_github_url (path: String) : String :=
  let pfx := "./build/lib/"
  let sfx := ".olean"
  assert!(pfx.isPrefixOf path)
  assert!(sfx.data.isSuffixOf path.data)
  "https://github.com/dwrensha/compfiles/blob/main/" ++
    ((path.stripPrefix pfx).stripSuffix sfx) ++ ".lean"

def HEADER : String :=
 "<!DOCTYPE html><html><head> <meta name=\"viewport\" content=\"width=device-width\">" ++
 "<title>Compfiles: Catalog of Math Problems Formalized in Lean</title>" ++
 "</head>"

def getBaseUrl : IO String := do
  let cwd ← IO.currentDir
  pure ((← IO.getEnv "GITHUB_PAGES_BASEURL").getD s!"file://{cwd}/_site/")

def htmlHeader (title : String) : IO String := do
  let baseurl ← getBaseUrl
  pure <|
    "<!DOCTYPE html><html><head>" ++
    "<meta name=\"viewport\" content=\"width=device-width\">" ++
    s!"<link rel=\"stylesheet\" type=\"text/css\" href=\"{baseurl}main.css\" >" ++
    s!"<title>{title}</title>" ++
    "</head>\n<body>"

unsafe def main (_args : List String) : IO Unit := do
  IO.FS.createDirAll "_site"
  IO.FS.createDirAll "_site/problems"
  IO.FS.writeFile "_site/main.css" (←IO.FS.readFile "scripts/main.css")

  let module := `Compfiles
  searchPathRef.set compile_time_search_path%

  withImportModules #[{module}] {} (trustLevel := 1024) fun env =>
    let ctx := {fileName := "", fileMap := default}
    let state := {env}
    Prod.fst <$> (CoreM.toIO · ctx state) do
      let mst ← ProblemExtraction.extractProblems

      let mut infos : List ProblemInfo := []
      for ⟨m, problem_src⟩ in mst do
          let p ← findOLean m
          let solutionUrl := olean_path_to_github_url p.toString
          IO.println s!"MODULE: {m}"
          let problemFile := s!"problems/{m}.html"
          let problemUrl := s!"{←getBaseUrl}{problemFile}"
          let homeUrl := s!"{←getBaseUrl}index.html"

          let mut proved := true
          let decls ← getDeclsInPackage m
          for d in decls do
            let c ← getConstInfo d
            match c.value? with
            | none => pure ()
            | some v => do
                 if v.hasSorry then proved := false
          infos := ⟨m.toString.stripPrefix "Compfiles.",
                    solutionUrl, problemUrl, proved⟩ :: infos

          let h ← IO.FS.Handle.mk ("_site/" ++ problemFile) IO.FS.Mode.write
          h.putStrLn <| ←htmlHeader m.toString
          if proved
          then
            h.putStrLn
              s!"<p>This problem <a href=\"{solutionUrl}\">has a complete solution</a>.</p>"
          else
            h.putStrLn
              s!"<p>This problem <a href=\"{solutionUrl}\">does not yet have a complete solution</a>.</p>"
          h.putStrLn "<pre class=\"problem\">"
          h.putStr (htmlEscape problem_src)
          h.putStrLn "</pre>"
          h.putStrLn "<br>"
          h.putStrLn s!"<a href=\"{homeUrl}\">full problem list</a>"
          h.putStrLn "</body></html>"
          h.flush

      -- now write the main index.html
      let num_proved := (infos.filter (·.proved)).length
      let commit_sha := ((← IO.getEnv "GITHUB_SHA").getD "GITHUB_SHA_env_var_not_found")
      let commit_url :=
        s!"https://github.com/dwrensha/compfiles/commit/{commit_sha}"

      let h ← IO.FS.Handle.mk "_site/index.html" IO.FS.Mode.write
      h.putStrLn <| ←htmlHeader "Compfiles: Catalog of Math Problems Formalized in Lean"
      h.putStr <| "<h2>" ++
         "<a href=\"https://github.com/dwrensha/compfiles\">" ++
         "Compfiles</a>: Catalog Of Math Problems Formalized In Lean.</h2>"
      h.putStr s!"<p>(Generated by commit <a href=\"{commit_url}\">{commit_sha}</a>.)<p>"
      h.putStr s!"<p>{num_proved} / {infos.length} problems have a complete solution.<p>"
      h.putStr "<ul>"
      let infos' := (infos.toArray.qsort (fun a1 a2 ↦ a1.name < a2.name)).toList
      for info in infos' do
        h.putStr "<li>"
        h.putStr s!"<a href=\"{info.solutionUrl}\">"
        if info.proved then
          h.putStr "☑  "
        else
          h.putStr "☐  "
        h.putStr "</a>"
        h.putStr s!"<a href=\"{info.problemUrl}\">{info.name}</a>"
        h.putStr "</li>"
      h.putStr "</ul>"
      h.putStr "</body></html>"
      pure ()
