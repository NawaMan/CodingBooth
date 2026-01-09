package nillable

type NillableString struct{ V *string }

func NewNillableString(value string) NillableString {
	return NillableString{V: &value}
}

func (thisString NillableString) IsSet() bool {
	return thisString.V != nil
}
func (thisString NillableString) Value() string {
	return thisString.ValueOr("")
}
func (thisString NillableString) ValueOr(fallback string) string {
	if thisString.V == nil {
		return fallback
	}
	return *thisString.V
}
func (thisString NillableString) ValueOrPanic(msg ...string) string {
	if thisString.V == nil {
		if len(msg) > 0 {
			panic(msg[0])
		}
		panic("NillableString: value is not set")
	}
	return *thisString.V
}

func (thisString *NillableString) Decode(value string) error {
	if value == "" {
		return nil
	}
	v := value
	thisString.V = &v
	return nil
}

// UnmarshalTOML implements the toml.Unmarshaler interface.
// It allows NillableString to be unmarshaled from a TOML string or left nil.
func (thisString *NillableString) UnmarshalTOML(data interface{}) error {
	if s, ok := data.(string); ok {
		thisString.V = &s
		return nil
	}
	return nil
}

func (thisString NillableString) String() string {
	if thisString.V == nil {
		return "<nil>"
	}
	return *thisString.V
}
