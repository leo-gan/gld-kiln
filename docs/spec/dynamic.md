# Dynamic values {#dynamic-values}

A dynamic value is a Kiln value whose schema arrives at run time as a JSON Schema document, rather than as a Mojo struct compiled into the program. The subset exists so a generator and a `Value` tree can share the Frozen layout without accepting every JSON Schema feature.

This page is that subset. A `tensors` field is not produced from it. A directory is built with the tensor API, not with `gld-kilngen-mojo`. The bytes of a struct the generator does emit are the same bytes as a hand-written struct. [Frozen values](frozen.md) is that layout.

## Why a subset exists

A subset exists because some programs do not have the Mojo struct at the moment they need a schema. A tool reads a JSON Schema file. A dynamic `Value` tree walks that schema at run time. If Kiln accepted every JSON Schema keyword, the generator would have to specify what `oneOf`, `pattern`, and unevaluated properties mean on a positional wire. Most of those keywords have no positional meaning. The subset is the keywords that do: booleans, integers with a width, numbers, strings, binary strings, arrays, objects, and `$ref` of the form `#/$defs/Name`.

The alternative is compile-time structs only. That is the fast path, and it is enough for a program that owns its types. It is not enough for a generator command, `gld-kilngen-mojo`, that must emit source from a file. Another alternative is to treat JSON itself as the wire. The schema file would be the schema, and the data file would repeat the names. That abandons the reason to use Kiln. A third alternative is to generate a `tensors` field from a JSON Schema extension. Kiln does not. A directory has dtypes, ranks, quantization, and opaque layouts. Pretending a JSON Schema array is that directory would either under-specify it or invent a second schema language. The tensor API builds the directory. The generator builds structs of scalars, strings, lists, and nested structs. Both use the same Frozen encoding, so a generated struct and a hand-written struct of the same fields produce the same bytes.

Optional fields are the one place the subset makes a wire choice. A property listed in `required` is present. A property left out of `required` is `opt<...>`. If `required` is omitted, every property is present. An object whose only value schema is `additionalProperties` is a dict, and dict keys are sorted. Those rules are small, and they are the difference between two byte strings, so they are specified rather than left to the generator's taste.

This is a good decision because one schema file can feed every language's generator without putting names on the wire. The cost is that a `tensors` field is written by hand, and that a JSON Schema which uses the rest of the standard is not a Kiln schema until it is reduced to this subset.

Analogy. A printer can fill a form from a written description of the boxes, provided the description only mentions boxes the press knows how to cut. A description that asks for a pop-up is not a form this press prints. The pop-up is a tensor directory. It is built on a different bench and then taped into the form.

| Choice | What it makes cheap | What it makes impossible | What still does that job |
| --- | --- | --- | --- |
| A documented subset of JSON Schema | One schema file can generate the struct | Expressing every JSON Schema keyword | The keywords listed below are the ones that generate a type |
| No `tensors` field from that subset | The generator stays on scalars, strings, lists, and structs | A generated struct whose field is a directory | The [tensor directory](tensor-directory.md), built beside the generated struct |

`schema_from_json` reads a JSON Schema subset: `boolean`, `integer` with an optional `format` (`int8` through `int64`, `uint8` through `uint64`), `number` (`float` or the default `double`), `string`, `string` with `"format": "binary"`, `array`, `object`, and `$ref` of the form `#/$defs/Name`. A property listed in `required` is present. A property left out of `required` is `opt<...>`. If `required` is omitted, every property is present. An object whose only value schema is `additionalProperties` is a `Dict[String, V]`.

The generator `gld-kilngen-mojo` emits one Mojo file of structs. Those structs use the same `encode` and `decode` as a hand-written struct. A `tensors` field is not produced from that JSON subset.
