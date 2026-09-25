// Enum output (upstream type_entry.rs `output_enum`, enums.rs `output_variant`).

///|
fn output_variant(
  variant : @typify.Variant,
  space : @typify.TypeSpace,
  output : OutputSpace,
  type_name : String,
) -> Tokens {
  let ident_name = variant.ident_name.unwrap()
  let variant_name = ident(ident_name)
  let doc = match variant.description {
    Some(s) => quote("#[doc = #s]", args={ "s": lit_str(s) })
    None => Tokens::new()
  }
  let serde = if variant.raw_name != ident_name {
    quote("#[serde(rename = #s)]", args={ "s": lit_str(variant.raw_name) })
  } else {
    Tokens::new()
  }
  let head = concat([doc, serde, variant_name])
  match variant.details {
    Simple => quote("#h,", args={ "h": head })
    Item(type_id) =>
      quote("#h(#t),", args={
        "h": head,
        "t": type_ident(space, entry(space, type_id), None),
      })
    Tuple(tuple) => {
      let types = tuple.map(id => type_ident(space, entry(space, id), None))
      if tuple.length() != 1 {
        quote("#h(#ts),", args={ "h": head, "ts": join(types, ',') })
      } else {
        // A one-element tuple variant keeps its tuple-ness.
        let inner = Tokens::from_array([Group(Paren, terminated(types, ','))])
        quote("#h(#inner),", args={ "h": head, "inner": inner })
      }
    }
    Struct(props) => {
      let streams = props.map(prop => {
        let prop_doc = match prop.description {
          Some(s) => quote("#[doc = #s]", args={ "s": lit_str(s) })
          None => Tokens::new()
        }
        let prop_entry = entry(space, prop.type_id)
        let (prop_serde, _) = generate_serde_attr(
          type_name + ident_name,
          prop.name,
          prop.rename,
          prop.state,
          prop_entry,
          space,
          output,
        )
        quote("#doc #serde #name: #ty,", args={
          "doc": prop_doc,
          "serde": prop_serde,
          "name": ident(prop.name),
          "ty": type_ident(space, prop_entry, None),
        })
      })
      quote("#h { #ps },", args={ "h": head, "ps": concat(streams) })
    }
  }
}

///|
let conversion_impls_template : String =
  #|impl ::std::convert::TryFrom<&str> for #type_name {
  #|    type Error = self::error::ConversionError;
  #|    fn try_from(value: &str) -> ::std::result::Result<Self, self::error::ConversionError> {
  #|        value.parse()
  #|    }
  #|}
  #|impl ::std::convert::TryFrom<::std::string::String> for #type_name {
  #|    type Error = self::error::ConversionError;
  #|    fn try_from(value: ::std::string::String) -> ::std::result::Result<Self, self::error::ConversionError> {
  #|        value.parse()
  #|    }
  #|}

///|
fn output_enum(
  space : @typify.TypeSpace,
  e : @typify.TypeEntry,
  output : OutputSpace,
  d : @typify.TypeEntryEnum,
  derive_set : Array[String],
) -> Unit {
  let doc = make_doc(d.name, d.description)
  let derive_set = derive_set.copy()
  if d.variants.iter().all(v => v.details is Simple) {
    derive_set.append(["Copy", "PartialOrd", "Ord", "PartialEq", "Eq", "Hash"])
  }
  let options : Array[Tokens] = []
  if d.rename is Some(old) {
    options.push(quote("rename = #s", args={ "s": lit_str(old) }))
  }
  match d.tag_type {
    External => ()
    Internal(tag~) =>
      options.push(quote("tag = #s", args={ "s": lit_str(tag) }))
    Adjacent(tag~, content~) => {
      options.push(quote("tag = #s", args={ "s": lit_str(tag) }))
      options.push(quote("content = #s", args={ "s": lit_str(content) }))
    }
    Untagged => options.push(quote("untagged"))
  }
  if d.deny_unknown_fields {
    options.push(quote("deny_unknown_fields"))
  }
  let serde = if options.is_empty() {
    Tokens::new()
  } else {
    quote("#[serde( #opts )]", args={ "opts": join(options, ',') })
  }
  let type_name = ident(d.name)
  let variants_decl = d.variants.map(v => {
    output_variant(v, space, output, d.name)
  })
  if d.tag_type == Untagged &&
    d.variants.filter(v => v.details is Simple).length() > 1 {
    abort("assertion failed: untagged enum with several simple variants")
  }
  let simple_enum_impl = if d.bespoke_impls.contains(AllSimpleVariants) {
    let display_arms = concat(
      d.variants.map(v => {
        quote("Self::#v => f.write_str(#s),", args={
          "v": ident(v.ident_name.unwrap()),
          "s": lit_str(v.raw_name),
        })
      }),
    )
    let from_str_arms = concat(
      d.variants.map(v => {
        quote("#s => Ok(Self::#v),", args={
          "v": ident(v.ident_name.unwrap()),
          "s": lit_str(v.raw_name),
        })
      }),
    )
    quote(
      (
        #|impl ::std::fmt::Display for #type_name {
        #|    fn fmt(&self, f: &mut ::std::fmt::Formatter<'_>) -> ::std::fmt::Result {
        #|        match *self { #display_arms }
        #|    }
        #|}
        #|impl ::std::str::FromStr for #type_name {
        #|    type Err = self::error::ConversionError;
        #|    fn from_str(value: &str) -> ::std::result::Result<Self, self::error::ConversionError> {
        #|        match value {
        #|            #from_str_arms
        #|            _ => Err("invalid value".into()),
        #|        }
        #|    }
        #|}
      ) +
      conversion_impls_template,
      args={
        "type_name": type_name,
        "display_arms": display_arms,
        "from_str_arms": from_str_arms,
      },
    )
  } else {
    Tokens::new()
  }
  let default_impl = match d.default {
    Some(value) => {
      guard output_value(space, e, value, Tokens::new()) is Some(v) else {
        abort("called `Option::unwrap()` on a `None` value (enum default)")
      }
      quote(
        "impl ::std::default::Default for #type_name { fn default() -> Self { #v } }",
        args={ "type_name": type_name, "v": v },
      )
    }
    None => Tokens::new()
  }
  let untagged_from_str = if d.bespoke_impls.contains(UntaggedFromStr) {
    let tries = concat(
      d.variants.map(v => {
        quote("if let Ok(v) = value.parse() { Ok(Self::#v(v)) } else", args={
          "v": ident(v.ident_name.unwrap()),
        })
      }),
    )
    quote(
      (
        #|impl ::std::str::FromStr for #type_name {
        #|    type Err = self::error::ConversionError;
        #|    fn from_str(value: &str) -> ::std::result::Result<Self, self::error::ConversionError> {
        #|        #tries { Err("string conversion failed for all variants".into()) }
        #|    }
        #|}
      ) +
      conversion_impls_template,
      args={ "type_name": type_name, "tries": tries },
    )
  } else {
    Tokens::new()
  }
  let untagged_display = if d.bespoke_impls.contains(UntaggedDisplay) {
    let arms = concat(
      d.variants.map(v => {
        quote("Self::#v(x) => x.fmt(f),", args={
          "v": ident(v.ident_name.unwrap()),
        })
      }),
    )
    quote(
      (
        #|impl ::std::fmt::Display for #type_name {
        #|    fn fmt(&self, f: &mut ::std::fmt::Formatter<'_>) -> ::std::fmt::Result {
        #|        match self { #arms }
        #|    }
        #|}
      ),
      args={ "type_name": type_name, "arms": arms },
    )
  } else {
    Tokens::new()
  }
  let convenience_from = concat(
    unique_payload_variants(d.variants).map(v => {
      match v.details {
        Item(type_id) => {
          let variant_type = entry(space, type_id)
          if variant_type.details is String {
            return Tokens::new()
          }
          quote(
            "impl ::std::convert::From<#t> for #type_name { fn from(value: #t) -> Self { Self::#v(value) } }",
            args={
              "t": type_ident(space, variant_type, None),
              "type_name": type_name,
              "v": ident(v.ident_name.unwrap()),
            },
          )
        }
        Tuple(type_ids) => {
          let idents = type_ids.map(id => {
            type_ident(space, entry(space, id), None)
          })
          let t = if type_ids.length() != 1 {
            Tokens::from_array([Group(Paren, join(idents, ','))])
          } else {
            Tokens::from_array([Group(Paren, terminated(idents, ','))])
          }
          let fields = concat(
            Array::makei(type_ids.length(), i => {
              quote("value.#i,", args={ "i": lit_int(i) })
            }),
          )
          quote(
            "impl ::std::convert::From<#t> for #type_name { fn from(value: #t) -> Self { Self::#v(#fields) } }",
            args={
              "t": t,
              "type_name": type_name,
              "v": ident(v.ident_name.unwrap()),
              "fields": fields,
            },
          )
        }
        _ => Tokens::new()
      }
    }),
  )
  let derives = strings_to_derives(
    derive_set,
    e.extra_derives,
    space.settings.extra_derives,
  )
  let attrs = strings_to_attrs(e.extra_attrs, space.settings.extra_attrs)
  let item = quote(
    "#doc #attrs #[derive(#derives)] #serde pub enum #type_name { #variants } #simple #default_impl #untagged_display #untagged_from_str #convenience_from",
    args={
      "doc": doc,
      "attrs": concat(attrs),
      "derives": join(derives, ','),
      "serde": serde,
      "type_name": type_name,
      "variants": concat(variants_decl),
      "simple": simple_enum_impl,
      "default_impl": default_impl,
      "untagged_display": untagged_display,
      "untagged_from_str": untagged_from_str,
      "convenience_from": convenience_from,
    },
  )
  output.add_item(Crate, d.name, item)
}

///|
/// Item/Tuple variants whose payload types appear in exactly one variant, in
/// variant order.
fn unique_payload_variants(
  variants : Array[@typify.Variant],
) -> Array[@typify.Variant] {
  let key = (v : @typify.Variant) => {
    match v.details {
      Item(id) => Some([id])
      Tuple(ids) => Some(ids)
      _ => None
    }
  }
  let counts : Map[String, Int] = Map([])
  let key_string = (ids : Array[@typify.TypeId]) => {
    ids.map(i => i.0.to_string()).join(",")
  }
  for v in variants {
    if key(v) is Some(ids) {
      let k = key_string(ids)
      counts[k] = counts.get(k).unwrap_or(0) + 1
    }
  }
  variants.filter(v => {
    match key(v) {
      Some(ids) => counts.get(key_string(ids)) == Some(1)
      None => false
    }
  })
}
