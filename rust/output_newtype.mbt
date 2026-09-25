// Newtype output (upstream type_entry.rs `output_newtype`).

///|
fn output_newtype(
  space : @typify.TypeSpace,
  e : @typify.TypeEntry,
  output : OutputSpace,
  d : @typify.TypeEntryNewtype,
  derive_set : Array[String],
) -> Unit raise @typify.TypifyError {
  let doc = make_doc(d.name, d.description)
  let type_name = ident(d.name)
  let inner_type = entry(space, d.type_id)
  let inner_type_name = type_ident(space, inner_type, None)
  let is_str = inner_type.details is String
  let derive_set = @collections.StrSet::from_array(derive_set)
  if is_str {
    for x in ["PartialOrd", "Ord", "PartialEq", "Eq", "Hash"] {
      derive_set.add(x)
    }
  }
  for x in space.settings.extra_derives {
    derive_set.add(x)
  }
  let args : Map[String, Tokens] = {
    "type_name": type_name,
    "inner": inner_type_name,
  }
  let constraint_impl = match d.constraints {
    NoConstraints => {
      let str_impl = if is_str {
        quote(
          "impl ::std::str::FromStr for #type_name { type Err = ::std::convert::Infallible; fn from_str(value: &str) -> ::std::result::Result<Self, Self::Err> { Ok(Self(value.to_string())) } }",
          args~,
        )
      } else {
        Tokens::new()
      }
      let from_str_impl = if has_impl(space, inner_type, FromStr) && !is_str {
        quote(
          "impl ::std::str::FromStr for #type_name { type Err = <#inner as ::std::str::FromStr>::Err; fn from_str(value: &str) -> ::std::result::Result<Self, Self::Err> { Ok(Self(value.parse()?)) } }",
          args~,
        )
      } else {
        Tokens::new()
      }
      let display_impl = if has_impl(space, inner_type, Display) {
        quote(
          "impl ::std::fmt::Display for #type_name { fn fmt(&self, f: &mut ::std::fmt::Formatter<'_>) -> ::std::fmt::Result { self.0.fmt(f) } }",
          args~,
        )
      } else {
        Tokens::new()
      }
      concat([
        quote(
          "impl ::std::convert::From<#inner> for #type_name { fn from(value: #inner) -> Self { Self(value) } }",
          args~,
        ),
        display_impl,
        str_impl,
        from_str_impl,
      ])
    }
    DenyValue(enum_values) | EnumValue(enum_values) => {
      let is_enum = d.constraints is EnumValue(_)
      if is_enum && is_str {
        raise @typify.TypifyError::Panic(
          "assertion failed: enumerated string newtype",
        )
      }
      derive_set.remove("::serde::Deserialize") |> ignore
      let value_output = enum_values.map(v => {
        output_value(space, inner_type, v, Tokens::new()).unwrap_or(
          Tokens::new(),
        )
      })
      let value_string = enum_values.map(v => v.to_string())
      let removed_a = derive_set.remove("schemars::JsonSchema")
      let has_json_schema = removed_a ||
        derive_set.remove("::schemars::JsonSchema")
      let from_strs = concat(
        value_string.map(s => {
          quote("::serde_json::from_str(#s).unwrap(),", args={ "s": lit_str(s) })
        }),
      )
      let json_schema = if !has_json_schema {
        Tokens::new()
      } else if is_enum {
        quote(
          (
            #|impl ::schemars::JsonSchema for #type_name {
            #|    fn schema_name() -> ::std::string::String { #name.to_string() }
            #|    fn json_schema(g: &mut ::schemars::r#gen::SchemaGenerator) -> ::schemars::schema::Schema {
            #|        let mut schema = <#inner as ::schemars::JsonSchema>::json_schema(g).into_object();
            #|        schema.enum_values = ::std::option::Option::Some([#values].into_iter().collect());
            #|        schema.into()
            #|    }
            #|}
          ),
          args={
            "type_name": type_name,
            "inner": inner_type_name,
            "name": lit_str(d.name),
            "values": from_strs,
          },
        )
      } else {
        quote(
          (
            #|impl ::schemars::JsonSchema for #type_name {
            #|    fn schema_name() -> ::std::string::String { #name.to_string() }
            #|    fn json_schema(g: &mut ::schemars::r#gen::SchemaGenerator) -> ::schemars::schema::Schema {
            #|        let mut schema = <#inner as ::schemars::JsonSchema>::json_schema(g).into_object();
            #|        let not = ::schemars::schema::SchemaObject {
            #|            enum_values: ::std::option::Option::Some([#values].into_iter().collect()),
            #|            ..::std::default::Default::default()
            #|        };
            #|        schema.subschemas().not = Some(::std::boxed::Box::new(not.into()));
            #|        schema.into()
            #|    }
            #|}
          ),
          args={
            "type_name": type_name,
            "inner": inner_type_name,
            "name": lit_str(d.name),
            "values": from_strs,
          },
        )
      }
      let not = if is_enum {
        Tokens::from_array([Punct('!', joint=false)])
      } else {
        Tokens::new()
      }
      quote(
        (
          #|impl ::std::convert::TryFrom<#inner> for #type_name {
          #|    type Error = self::error::ConversionError;
          #|    fn try_from(value: #inner) -> ::std::result::Result<Self, self::error::ConversionError> {
          #|        if #not [#values].contains(&value) {
          #|            Err("invalid value".into())
          #|        } else {
          #|            Ok(Self(value))
          #|        }
          #|    }
          #|}
          #|impl<'de> ::serde::Deserialize<'de> for #type_name {
          #|    fn deserialize<D>(deserializer: D,) -> ::std::result::Result<Self, D::Error>
          #|    where
          #|        D: ::serde::Deserializer<'de>,
          #|    {
          #|        Self::try_from(<#inner>::deserialize(deserializer)?,)
          #|            .map_err(|e| { <D::Error as ::serde::de::Error>::custom(e.to_string(),) })
          #|    }
          #|}
          #|#json_schema
        ),
        args={
          "type_name": type_name,
          "inner": inner_type_name,
          "not": not,
          "values": terminated(value_output, ','),
          "json_schema": json_schema,
        },
      )
    }
    String(max_length~, min_length~, pattern~) => {
      let max = match max_length {
        Some(v) =>
          quote("if value.chars().count() > #v { return Err(#err.into()); }", args={
            "v": lit_usize(v.reinterpret_as_int()),
            "err": lit_str("longer than \{v} characters"),
          })
        None => Tokens::new()
      }
      let min = match min_length {
        Some(v) =>
          quote("if value.chars().count() < #v { return Err(#err.into()); }", args={
            "v": lit_usize(v.reinterpret_as_int()),
            "err": lit_str("shorter than \{v} characters"),
          })
        None => Tokens::new()
      }
      let pat = match pattern {
        Some(p) =>
          quote(
            (
              #|static PATTERN: ::std::sync::LazyLock<::regress::Regex> = ::std::sync::LazyLock::new(|| {
              #|    ::regress::Regex::new(#p).unwrap()
              #|});
              #|if PATTERN.find(value).is_none() {
              #|    return Err(#err.into());
              #|}
            ),
            args={
              "p": lit_str(p),
              "err": lit_str("doesn't match pattern \"\{p}\""),
            },
          )
        None => Tokens::new()
      }
      derive_set.remove("::serde::Deserialize") |> ignore
      quote(
        (
          #|impl ::std::str::FromStr for #type_name {
          #|    type Err = self::error::ConversionError;
          #|    fn from_str(value: &str) -> ::std::result::Result<Self, self::error::ConversionError> {
          #|        ::std::convert::TryFrom::try_from(value)
          #|    }
          #|}
          #|impl ::std::convert::TryFrom<&str> for #type_name {
          #|    type Error = self::error::ConversionError;
          #|    fn try_from(value: &str) -> ::std::result::Result<Self, self::error::ConversionError> {
          #|        #max #min #pat
          #|        Ok(Self(value.to_string()))
          #|    }
          #|}
          #|impl ::std::convert::TryFrom<::std::string::String> for #type_name {
          #|    type Error = self::error::ConversionError;
          #|    fn try_from(value: ::std::string::String) -> ::std::result::Result<Self, self::error::ConversionError> {
          #|        ::std::convert::TryFrom::try_from(value.as_str())
          #|    }
          #|}
          #|impl<'de> ::serde::Deserialize<'de> for #type_name {
          #|    fn deserialize<D>(deserializer: D,) -> ::std::result::Result<Self, D::Error>
          #|    where
          #|        D: ::serde::Deserializer<'de>,
          #|    {
          #|        ::std::convert::TryFrom::try_from(::std::string::String::deserialize(deserializer)?,)
          #|            .map_err(|e: self::error::ConversionError| {
          #|                <D::Error as ::serde::de::Error>::custom(e.to_string(),)
          #|            })
          #|    }
          #|}
        ),
        args={ "type_name": type_name, "max": max, "min": min, "pat": pat },
      )
    }
  }
  let vis = if d.constraints is NoConstraints {
    ident("pub")
  } else {
    Tokens::new()
  }
  let default_impl = match d.default {
    Some(value) => {
      guard output_value(space, e, value, Tokens::new()) is Some(v) else {
        raise @typify.TypifyError::Panic(
          "called `Option::unwrap()` on a `None` value (newtype default)",
        )
      }
      quote(
        "impl ::std::default::Default for #type_name { fn default() -> Self { #v } }",
        args={ "type_name": type_name, "v": v },
      )
    }
    None => Tokens::new()
  }
  let derives = strings_to_derives(derive_set.to_array(), e.extra_derives, [])
  let attrs = strings_to_attrs(e.extra_attrs, space.settings.extra_attrs)
  let item = quote(
    (
      #|#doc #attrs #[derive(#derives)] #[serde(transparent)]
      #|pub struct #type_name(#vis #inner);
      #|impl ::std::ops::Deref for #type_name {
      #|    type Target = #inner;
      #|    fn deref(&self) -> &#inner { &self.0 }
      #|}
      #|impl ::std::convert::From<#type_name> for #inner {
      #|    fn from(value: #type_name) -> Self { value.0 }
      #|}
      #|#default_impl #constraint_impl
    ),
    args={
      "doc": doc,
      "attrs": concat(attrs),
      "derives": join(derives, ','),
      "type_name": type_name,
      "vis": vis,
      "inner": inner_type_name,
      "default_impl": default_impl,
      "constraint_impl": constraint_impl,
    },
  )
  output.add_item(Crate, d.name, item)
}

///|
fn has_impl(
  space : @typify.TypeSpace,
  e : @typify.TypeEntry,
  impl_name : @typify.TypeSpaceImpl,
) -> Bool {
  e.has_impl(space, impl_name) catch {
    err => abort("has_impl: \{err}")
  }
}
