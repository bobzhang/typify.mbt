// Table-driven struct decoding: the key loop of a serde-derived struct
// visitor (named fields, duplicates, unknown fields, flatten buffering) and
// its positional form, with the per-field decoding supplied by generated
// code as a callback.

///|
/// The JSON names of a struct's named (non-flattened) fields, in
/// declaration order, with an index for lookups. Generated code builds one
/// per struct, once.
pub struct Fields {
  priv names : Array[String]
  priv index : Map[String, Int]
}

///|
pub fn Fields::new(names : Array[String]) -> Fields {
  let index = Map::new(capacity=names.length())
  for i, n in names {
    // serde matches the first field with a given name.
    if !index.contains(n) {
      index[n] = i
    }
  }
  { names, index, }
}

///|
/// How the fields were provided.
priv enum FieldsForm {
  Named(FlatBuf?)
  Positional(String)
}

///|
/// The result of `de_fields`: resolves absent fields after the input has
/// been read.
pub struct FieldsInput {
  priv fields : Fields
  priv form : FieldsForm
}

///|
/// Read a struct's fields from `d`, calling `on_field(i, value)` for field
/// `i` in input order (serde decodes each value when its key is read).
///
/// - `flatten`: the struct has flattened fields; unknown entries are
///   buffered for them and positional input is rejected.
/// - `deny`: `deny_unknown_fields`.
/// - `positional`: whether a sequence of field values is accepted.
/// - `external_variant`: the payload of an externally tagged struct variant.
///
/// Duplicate keys are rejected before their second value is decoded.
/// Positional elements past the last field are rejected after all fields
/// have been read.
pub fn de_fields(
  d : De,
  expecting : String,
  fields : Fields,
  on_field : (Int, De) -> Unit raise DeError,
  flatten? : Bool = false,
  deny? : Bool = false,
  positional? : Bool = true,
  external_variant? : Bool = false,
) -> FieldsInput raise DeError {
  let input = de_struct(d, expecting, fields.names, flatten, external_variant~)
  match input {
    Entries(entries) => {
      let seen = FixedArray::make(fields.names.length(), false)
      let buf = if flatten { Some(FlatBuf::new()) } else { None }
      for e in entries {
        let (key, value) = e
        match fields.index.get(key) {
          Some(i) => {
            if seen[i] {
              raise duplicate_field_error(key)
            }
            seen[i] = true
            on_field(i, value)
          }
          None =>
            match buf {
              Some(b) => b.push(key, value)
              None => if deny { raise unknown_field_error(key, fields.names) }
            }
        }
      }
      { fields, form: Named(buf), }
    }
    Elements(s) => {
      if !positional {
        raise DeError("invalid type: sequence, expected \{expecting}")
      }
      let expected = s.expected
      for i in 0..<fields.names.length() {
        match s.next_opt() {
          Some(v) => on_field(i, v)
          None => break
        }
      }
      if s.pos == fields.names.length() {
        s.finish()
      }
      { fields, form: Positional(expected), }
    }
  }
}

///|
/// The deserializer for absent field `i` (`Missing` for named input, which
/// lets `Option` fields become `None`); positional input reports an invalid
/// length.
pub fn FieldsInput::absent(self : FieldsInput, i : Int) -> De raise DeError {
  match self.form {
    Named(_) => Missing(self.fields.names[i])
    Positional(expected) =>
      raise DeError("invalid length \{i}, expected \{expected}")
  }
}

///|
/// The error for a required field `i` that reports its own absence
/// (`deserialize_with`).
pub fn FieldsInput::absent_error(self : FieldsInput, i : Int) -> DeError {
  match self.form {
    Named(_) => missing_error(self.fields.names[i])
    Positional(expected) => DeError("invalid length \{i}, expected \{expected}")
  }
}

///|
/// The deserializer for a flattened field: the buffered unknown entries.
pub fn FieldsInput::flat(self : FieldsInput) -> De {
  match self.form {
    Named(Some(buf)) => Flat(buf)
    _ => abort("FieldsInput::flat: the struct has no flattened fields")
  }
}

///|
/// `deny_unknown_fields` with flattened fields: entries no flattened field
/// claimed.
pub fn FieldsInput::deny_leftovers(self : FieldsInput) -> Unit raise DeError {
  if self.form is Named(Some(buf)) {
    buf.deny_leftovers()
  }
}
