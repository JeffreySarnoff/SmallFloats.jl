# External Reference

Docstrings for the documented **public** surface — the exported names. The full
export list is far larger (400+ names, including the 120 exported format aliases
— the other 384 are opt-in via `using SmallFloats.Formats` — the
predefined projection-spec grid, and the generated operation and block
registers); names without docstrings are covered descriptively in the
[User Guide](@ref); unexported machinery is in the
[Internal Reference](@ref).

```@autodocs
Modules = [SmallFloats]
Private = false
```
