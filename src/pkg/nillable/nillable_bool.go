package nillable

import (
	"strconv"
	"strings"
)

type NillableBool struct{ V *bool }

func NewNillableBool(value bool) NillableBool {
	return NillableBool{V: &value}
}

func (thisBool NillableBool) IsSet() bool {
	return thisBool.V != nil
}
func (thisBool NillableBool) Value() bool {
	return thisBool.ValueOr(false)
}
func (thisBool NillableBool) ValueOr(fallback bool) bool {
	if thisBool.V == nil {
		return fallback
	}
	return *thisBool.V
}
func (thisBool NillableBool) ValueOrPanic(msg ...string) bool {
	if thisBool.V == nil {
		if len(msg) > 0 {
			panic(msg[0])
		}
		panic("NillableBool: value is not set")
	}
	return *thisBool.V
}

func (thisBool *NillableBool) Decode(value string) error {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil
	}
	v, err := strconv.ParseBool(value)
	if err != nil {
		return err
	}
	thisBool.V = &v // v escapes; safe
	return nil
}

// UnmarshalTOML implements the toml.Unmarshaler interface.
// It allows NillableBool to be unmarshaled from a TOML boolean or left nil.
func (thisBool *NillableBool) UnmarshalTOML(data interface{}) error {
	if b, ok := data.(bool); ok {
		thisBool.V = &b
		return nil
	}
	return nil
}
