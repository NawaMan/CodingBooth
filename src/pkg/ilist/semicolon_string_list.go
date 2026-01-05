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
