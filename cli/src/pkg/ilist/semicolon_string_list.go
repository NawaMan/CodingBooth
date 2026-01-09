package ilist

import "strings"

type SemicolonStringList struct {
	List[string]
}

func (s *SemicolonStringList) Decode(value string) error {
	if strings.TrimSpace(value) == "" {
		s.elements = nil
		return nil
	}

	parts := strings.Split(value, ";")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p == "" {
			continue
		}
		out = append(out, p)
	}

	s.elements = out
	return nil
}

func (s *SemicolonStringList) Clone() SemicolonStringList {
	return SemicolonStringList{List: s.List.Clone()}
}

// UnmarshalTOML implements the toml.Unmarshaler interface.
// This allows TOML to decode a string value into a SemicolonStringList.
func (s *SemicolonStringList) UnmarshalTOML(data interface{}) error {
	str, ok := data.(string)
	if !ok {
		return nil // Let TOML handle type errors
	}
	return s.Decode(str)
}
