// Struct output (upstream type_entry.rs `output_struct`).

///|
priv enum PropDefault {
  NoDefault(String)
  DefaultValue(Tokens)
  CustomValue(Tokens)
}

///|
fn output_struct(
  space : @typify.TypeSpace,
  e : @typify.TypeEntry,
  output : OutputSpace,
  d : @typify.TypeEntryStruct,
  derive_set : Array[String],
) -> Unit raise @typify.TypifyError {
  let doc = make_doc(d.name, d.description)
  let options : Array[Tokens] = []
  if d.rename is Some(old) {
    options.push(quote("rename = #s", args={ "s": lit_str(old) }))
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
  let prop_doc = []
  let prop_serde = []
  let prop_default : Array[PropDefault] = []
  let prop_name = []
  let prop_error = []
  let prop_type = []
  let prop_type_scoped = []
  for prop in d.properties {
    prop_doc.push(
      match prop.description {
        Some(s) => quote("#[doc = #s]", args={ "s": lit_str(s) })
        None => Tokens::new()
      },
    )
    prop_name.push(ident(prop.name))
    prop_error.push("error converting supplied value for \{prop.name}: {e}")
    let prop_entry = entry(space, prop.type_id)
    prop_type.push(type_ident(space, prop_entry, None))
    prop_type_scoped.push(type_ident(space, prop_entry, Some("super")))
    let (serde, default_fn) = generate_serde_attr(
      d.name,
      prop.name,
      prop.rename,
      prop.state,
      prop_entry,
      space,
      output,
    )
    prop_serde.push(serde)
    prop_default.push(
      match default_fn {
        DefaultDefault => DefaultValue(quote("Default::default()"))
        Custom(fn_name) =>
          CustomValue(quote("#f()", args={ "f": path_tokens(fn_name) }))
        NoDefault => NoDefault("no value supplied for \{prop.name}")
      },
    )
  }
  // `#[derive(Default)]` when the manual impl would be exactly that.
  let derive_default = d.default is None &&
    prop_default.iter().all(pd => pd is DefaultValue(_))
  let derive_set = derive_set.copy()
  if derive_default {
    derive_set.push("Default")
  }
  let derives = strings_to_derives(
    derive_set,
    e.extra_derives,
    space.settings.extra_derives,
  )
  let attrs = strings_to_attrs(e.extra_attrs, space.settings.extra_attrs)
  let fields = concat(
    Array::makei(prop_name.length(), i => {
      quote("#doc #serde pub #name: #ty,", args={
        "doc": prop_doc[i],
        "serde": prop_serde[i],
        "name": prop_name[i],
        "ty": prop_type[i],
      })
    }),
  )
  output.add_item(
    Crate,
    d.name,
    quote(
      "#doc #attrs #[derive(#derives)] #serde pub struct #type_name { #fields }",
      args={
        "doc": doc,
        "attrs": concat(attrs),
        "derives": join(derives, ','),
        "serde": serde,
        "type_name": type_name,
        "fields": fields,
      },
    ),
  )
  let default_impl_template = "impl ::std::default::Default for #type_name { fn default() -> Self { #body } }"
  match d.default {
    Some(value) => {
      guard output_value(space, e, value, Tokens::new()) is Some(v) else {
        raise @typify.TypifyError::Panic(
          "called `Option::unwrap()` on a `None` value (struct default)",
        )
      }
      output.add_item(
        Crate,
        d.name,
        quote(default_impl_template, args={ "type_name": type_name, "body": v }),
      )
    }
    None =>
      if !derive_default && prop_default.iter().all(pd => !(pd is NoDefault(_))) {
        let inits = concat(
          Array::makei(prop_name.length(), i => {
            let v = match prop_default[i] {
              DefaultValue(t) | CustomValue(t) => t
              NoDefault(_) => raise @typify.TypifyError::Panic("unreachable")
            }
            quote("#n: #v,", args={ "n": prop_name[i], "v": v })
          }),
        )
        output.add_item(
          Crate,
          d.name,
          quote(default_impl_template, args={
            "type_name": type_name,
            "body": quote("Self { #inits }", args={ "inits": inits }),
          }),
        )
      }
  }
  if !space.settings.struct_builder {
    return
  }
  output.add_item(
    Crate,
    d.name,
    quote(
      "impl #type_name { pub fn builder() -> builder::#type_name { Default::default() } }",
      args={ "type_name": type_name },
    ),
  )
  let value_ident = if prop_name.is_empty() {
    ident("_value")
  } else {
    ident("value")
  }
  let builder_defaults = prop_default.map(pd => {
    match pd {
      NoDefault(msg) => quote("Err(#m.to_string())", args={ "m": lit_str(msg) })
      DefaultValue(t) => quote("Ok(#t)", args={ "t": t })
      CustomValue(t) => quote("Ok(super::#t)", args={ "t": t })
    }
  })
  let n = prop_name.length()
  let each = (f : (Int) -> Tokens) => concat(Array::makei(n, f))
  let fields = each(i => {
    quote("#n: ::std::result::Result<#t, ::std::string::String>,", args={
      "n": prop_name[i],
      "t": prop_type_scoped[i],
    })
  })
  let defaults = each(i => {
    quote("#n: #v,", args={ "n": prop_name[i], "v": builder_defaults[i] })
  })
  let setters = each(i => {
    quote(
      (
        #|pub fn #n<T>(mut self, value: T) -> Self
        #|where
        #|    T: ::std::convert::TryInto<#t>,
        #|    T::Error: ::std::fmt::Display,
        #|{
        #|    self.#n = value.try_into().map_err(|e| format!(#err));
        #|    self
        #|}
      ),
      args={
        "n": prop_name[i],
        "t": prop_type_scoped[i],
        "err": lit_str(prop_error[i]),
      },
    )
  })
  let try_fields = each(i => quote("#n: value.#n?,", args={ "n": prop_name[i] }))
  let from_fields = each(i => {
    quote("#n: Ok(value.#n),", args={ "n": prop_name[i] })
  })
  output.add_item(
    Builder,
    d.name,
    quote(
      (
        #|#[derive(Clone, Debug)]
        #|pub struct #type_name { #fields }
        #|impl ::std::default::Default for #type_name {
        #|    fn default() -> Self { Self { #defaults } }
        #|}
        #|impl #type_name { #setters }
        #|impl ::std::convert::TryFrom<#type_name> for super::#type_name {
        #|    type Error = super::error::ConversionError;
        #|    fn try_from(#value_ident: #type_name) -> ::std::result::Result<Self, super::error::ConversionError> {
        #|        Ok(Self { #try_fields })
        #|    }
        #|}
        #|impl ::std::convert::From<super::#type_name> for #type_name {
        #|    fn from(#value_ident: super::#type_name) -> Self {
        #|        Self { #from_fields }
        #|    }
        #|}
      ),
      args={
        "type_name": type_name,
        "fields": fields,
        "defaults": defaults,
        "setters": setters,
        "value_ident": value_ident,
        "try_fields": try_fields,
        "from_fields": from_fields,
      },
    ),
  )
}
