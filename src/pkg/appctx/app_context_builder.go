package appctx

import "github.com/nawaman/workspace/src/pkg/ilist"

// AppContextBuilder is a mutable builder for constructing AppContext instances.
type AppContextBuilder struct {

	// constant
	PrebuildRepo string
	WsVersion    string
	SetupsDir    string

	// taken from the script runtime
	ScriptName string
	ScriptDir  string
	LibDir     string

	// derived from variant
	HasNotebook bool
	HasVscode   bool
	HasDesktop  bool

	// derived from DinD
	CreatedDindNet bool

	// derived from image determination of image
	RunMode    string
	LocalBuild bool
	ImageMode  string

	// derived from all the context processing
	CommonArgs *ilist.AppendableList[string]
	BuildArgs  *ilist.AppendableList[string]
	RunArgs    *ilist.AppendableList[string]
	Cmds       *ilist.AppendableList[string]

	// derived from port determination
	PortGenerated bool
	PortNumber    int

	// Configurable
	Config AppConfig
}

// Build creates an immutable AppContext snapshot from this builder.
func (builder *AppContextBuilder) Build() AppContext {
	return NewAppContext(builder)
}

// Clone the content of the app context builder.
func (builder *AppContextBuilder) Clone() *AppContextBuilder {
	copy := *builder

	copy.CommonArgs = cloneAppendableList(builder.CommonArgs)
	copy.BuildArgs = cloneAppendableList(builder.BuildArgs)
	copy.RunArgs = cloneAppendableList(builder.RunArgs)
	copy.Cmds = cloneAppendableList(builder.Cmds)

	copy.Config = *builder.Config.Clone()

	return &copy
}

// Clone the content of the appendable list.
func cloneAppendableList(list *ilist.AppendableList[string]) *ilist.AppendableList[string] {
	if list == nil {
		return ilist.NewAppendableList[string]()
	}
	return list.Clone()
}
