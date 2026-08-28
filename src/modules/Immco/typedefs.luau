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

export type WidgetParams = {
	engine_window: any,
	x: number,
	y: number,
	width: number,
	height: number,
	theme: Theme,
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

return {}
