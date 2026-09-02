export type RGBA = {
	R: number,
	G: number,
	B: number,
	A: number,
}

export type Theme = {
	BgColor: RGBA,
	AccentColor: RGBA,
	SecondaryTextColor: RGBA,
	Font: string,
	FontBold: string,
	SecondaryColor: RGBA,
	CornerRadius: number,
}

export type TableCell = string | number | {
	Text: string?,
	Color: RGBA?,
	Align: ("left" | "center" | "right")?,
}

export type TableParams = {
	x: number,
	y: number,
	width: number,
	engine_window: any,
	theme: any,
	RetainedStorage: { [string]: any },
	id: string,
	renderer: any,
	Data: { { TableCell } },
	HasHeader: boolean?,
	ColumnWidths: { number }?,
	ColumnAlign: { "left" | "center" | "right" }?,
	RowHeight: number?,
	HeaderHeight: number?,
	MaxVisibleRows: number?,
	CellPadding: number?,
	TextSize: number?,
	CornerRadius: number?,
	ShowGridLines: boolean?,
	StripeRows: boolean?,
	Align: ("left" | "center" | "right")?,
	HeaderAlign: ("left" | "center" | "right")?,
	HeaderColor: RGBA?,
	HeaderTextColor: RGBA?,
	HoverColor: RGBA?,
	StripeColor: RGBA?,
	ScrollSpeed: number?,
	ScrollLerpSpeed: number?,
	OnCellClicked: ((row: number, col: number, value: any) -> ())?,
}

export type BreadcrumbItem = {
	Text: string,
	Current: boolean?,
	Disabled: boolean?,
	OnClick: (() -> ())?,
}

export type BreadcrumbParams = {
	x: number,
	y: number,
	height: number?,

	engine_window: any,
	renderer: any,
	theme: any,

	Items: { BreadcrumbItem },

	TextSize: number?,
	Font: string?,
	TextShadow: boolean?,

	ShadowColor: RGBA?,
	ShadowOffsetX: number?,
	ShadowOffsetY: number?,

	ShadowBlur: number?,
	ShadowSpread: number?,

	Gap: number?,
	Separator: string?,

	Collapsed: boolean?,
	Ellipsis: string?,
	OnEllipsisClick: ((hiddenItems: { BreadcrumbItem }) -> ())?,

	LinkColor: RGBA?,
	HoverColor: RGBA?,
	PageColor: RGBA?,
	SeparatorColor: RGBA?,
}

export type TabItem = {
	Value: string,
	Text: string?,

	Icon: Image?,
	Count: number?,

	Width: number?,
	Height: number?,

	Disabled: boolean?,

	CountColor: RGBA?,

	Content: ((params: any, dt: number) -> ())?,
}

export type TabsParams = {
	x: number,
	y: number,

	width: number?,
	height: number?,

	engine_window: any,
	renderer: any,
	theme: any,

	RetainedStorage: { [any]: any }?,
	id: any?,

	Items: { TabItem },

	Orientation: ("horizontal" | "vertical")?,
	Variant: ("filled" | "underline")?,

	Value: string?,
	DefaultValue: string?,

	OnChange: ((value: string) -> ())?,

	TextSize: number?,
	Font: string?,

	TabWidth: number?,
	TabHeight: number?,

	PaddingX: number?,
	Gap: number?,

	IconSize: number?,
	IconGap: number?,
	CountGap: number?,

	CornerRadius: number?,
	ActiveInset: number?,

	BackgroundColor: RGBA?,
	ActiveColor: RGBA?,
	HoverColor: RGBA?,

	TextColor: RGBA?,
	ActiveTextColor: RGBA?,
	DisabledTextColor: RGBA?,

	CountColor: RGBA?,

	IndicatorColor: RGBA?,
	IndicatorThickness: number?,

	Animated: boolean?,
	AnimationSpeed: number?,

	RenderContent: boolean?,

	ContentGap: number?,
	ContentWidth: number?,
	ContentHeight: number?,
}

export type KbdParams = {
	x: number,
	y: number,

	width: number?,
	height: number?,

	engine_window: any,
	theme: any,

	Text: string?,

	Size: ("xs" | "sm" | "md" | "lg" | "xl")?,

	TextSize: number?,
	Font: string?,

	PaddingX: number?,
	CornerRadius: number?,

	BorderThickness: number?,
	BottomBorderExtra: number?,

	BackgroundColor: RGBA?,
	BorderColor: RGBA?,
	TextColor: RGBA?,
}

export type ButtonGroupItem = {
	Type: ("Button" | "Text" | "Separator")?,

	Text: string?,

	Icon: Image?,
	IconSize: number?,
	IconPosition: ("left" | "right")?,

	Width: number?,
	Height: number?,

	Disabled: boolean?,
	OnClick: (() -> ())?,

	Color: RGBA?,
	HoverColor: RGBA?,
	PressedColor: RGBA?,

	TextColor: RGBA?,
	DisabledTextColor: RGBA?,

	Thickness: number?,
}

export type ButtonGroupParams = {
	x: number,
	y: number,

	width: number?,
	height: number?,

	engine_window: any,
	renderer: any,
	theme: any,

	Items: { ButtonGroupItem },

	Orientation: ("horizontal" | "vertical")?,

	TextSize: number?,
	Font: string?,

	ItemHeight: number?,
	PaddingX: number?,

	IconSize: number?,
	IconGap: number?,

	CornerRadius: number?,

	BackgroundColor: RGBA?,
	ButtonColor: RGBA?,
	HoverColor: RGBA?,
	PressedColor: RGBA?,

	TextColor: RGBA?,
	MutedTextColor: RGBA?,

	BorderColor: RGBA?,
	DividerColor: RGBA?,

	SeparatorColor: RGBA?,
	SeparatorThickness: number?,
	SeparatorInset: number?,

	ShowBorder: boolean?,
	ShowDividers: boolean?,
}

export type WidgetParams = {
	engine_window: any,
	x: number,
	y: number,
	width: number,
	height: number,
	theme: Theme,
	title: string?,
	tabs: { { title: string } }?,
	activeTab: number?,
	OnTabChanged: ((index: number, tab: { title: string }) -> ())?,
	callback: () -> ()?,
}

export type ColorPickerParams = {
	RetainedStorage: { [any]: any },
	id: any,
	renderer: any,
	window: any,
	theme: any,
	x: number,
	y: number,
	Size: number?,
	HueBarWidth: number?,
	ShowAlpha: boolean?,
	AlphaBarWidth: number?,
	Gap: number?,
	Resolution: number?,
	HueSegments: number?,
	CheckerSize: number?,
	InitialColor: RGBA,
	OnChanged: ((color: RGBA) -> ())?,
	CornerRadius: number?,
	ShowPreview: boolean?,
	ShowHex: boolean?,
	PreviewHeight: number?,
}

export type ScrollerParams = {
	x: number,
	y: number,
	width: number,
	height: number,

	id: string,
	renderer: any,
	window: typedefs.Window,
	theme: any,
	RetainedStorage: { [string]: any },

	ContentHeight: number?,
	ViewHeight: number?,
	Orientation: ("vertical" | "horizontal")?,

	ScrollSpeed: number?,
	ScrollLerpSpeed: number?,
	MinThumbSize: number?,
	CornerRadius: number?,

	TrackColor: RGBA?,
	ThumbColor: RGBA?,
	ThumbHoverColor: RGBA?,
	ThumbActiveColor: RGBA?,

	ScrollRegion: { x: number, y: number, width: number, height: number }?,

	InitialScroll: number?,
	OnScroll: ((number) -> ())?,

	ContentX: number?,
	ContentY: number?,
	ContentWidth: number?,
	callback: ((any) -> ())?,
}

export type BooleanParams = {
	engine_window: any,
	x: number,
	y: number,
	width: number,
	height: number,
	theme: Theme,
	bool: boolean,
	callback: () -> ()?,
}

export type ImageParams = {
	engine_window: any,
	x: number,
	y: number,
	width: number,
	height: number,
	theme: Theme,
	Image: { _handle: any },
	callback: () -> ()?,
}

export type TextParams = {
	text: string?,
	TextSize: number?,
	Font: string?,
	Color: RGBA?,
	x: number,
	y: number,
}

export type Image = { _handle: {} }

export type ImageButtonParams = {
	engine_window: any,
	x: number,
	y: number,
	width: number,
	height: number,
	theme: Theme,
	Color: any,
	Image: Image,
	padding: number?,
	imageWidth: number?,
	imageHeight: number?,
	preserveAspectRatio: boolean?,
	imageAspectRatio: number?,
}

export type TextButtonParams = WidgetParams & TextParams
export type ImageTextButtonParams = ImageButtonParams & TextButtonParams

return {}
