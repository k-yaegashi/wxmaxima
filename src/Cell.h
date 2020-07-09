// -*- mode: c++; c-file-style: "linux"; c-basic-offset: 2; indent-tabs-mode: nil -*-
//
//  Copyright (C) 2004-2015 Andrej Vodopivec <andrej.vodopivec@gmail.com>
//  Copyright (C) 2014-2018 Gunter Königsmann <wxMaxima@physikbuch.de>
//  Copyright (C) 2020      Kuba Ober <kuba@bertec.com>
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
//
//  SPDX-License-Identifier: GPL-2.0+

/*! \file
  
  The definition of the base class of all cells the worksheet consists of.
 */

#ifndef MATHCELL_H
#define MATHCELL_H

#include "precomp.h"
#include "CellPtr.h"
#include "Configuration.h"
#include "TextStyle.h"
#include <wx/defs.h>
#if wxUSE_ACCESSIBILITY
#include "wx/access.h"
#endif // wxUSE_ACCESSIBILITY
#include <algorithm>
#include <map>
#include <memory>
#include <vector>

class EditorCell;
class GroupCell;
class TextCell;
class Worksheet;
class wxXmlNode;

/*! The supported types of math cells
 */
enum CellType
{
  MC_TYPE_DEFAULT,
  MC_TYPE_MAIN_PROMPT, //!< Input labels
  MC_TYPE_PROMPT,      //!< Maxima questions or lisp prompts
  MC_TYPE_LABEL,       //!< An output label generated by maxima
  MC_TYPE_INPUT,       //!< A cell containing code
  MC_TYPE_WARNING,     //!< A warning output by maxima
  MC_TYPE_ERROR,       //!< An error output by maxima
  MC_TYPE_TEXT,        //!< Text that isn't passed to maxima
  MC_TYPE_SUBSECTION,  //!< A subsection name
  MC_TYPE_SUBSUBSECTION,  //!< A subsubsection name
  MC_TYPE_HEADING5,  //!< A subsubsection name
  MC_TYPE_HEADING6,  //!< A subsubsection name
  MC_TYPE_SECTION,     //!< A section name
  MC_TYPE_TITLE,       //!< The title of the document
  MC_TYPE_IMAGE,       //!< An image
  MC_TYPE_SLIDE,       //!< An animation created by the with_slider_* maxima commands
  MC_TYPE_GROUP        //!< A group cells that bundles several individual cells together
};

/*!
  The base class all cell types the worksheet can consist of are derived from

  Every Cell is part of two double-linked lists:
   - A Cell does have a member m_previous that points to the previous item
     (or contains a NULL for the head node of the list) and a member named m_next 
     that points to the next cell (or contains a NULL if this is the end node of a list).
   - And there is m_nextToDraw that contain fractions and similar 
     items as one element if they are drawn as a single 2D object that isn't divided by
     a line break, but will contain every single element of a fraction as a separate 
     object if the fraction is broken into several lines and therefore displayed in its
     a linear form.

  Also every list of Cells can be a branch of a tree since every math cell contains
  a pointer to its parent group cell.

  Besides the cell types that are directly user visible there are cells for several
  kinds of items that are displayed in a special way like abs() statements (displayed
  as horizontal rules), subscripts, superscripts and exponents.
  Another important concept realized by a class derived from this one is
  the group cell that groups all things that are foldable in the gui like:
   - A combination of maxima input with the output, the input prompt and the output 
     label.
   - A chapter or a section and
   - Images with their title (or the input cells that generated them)
   .

  \attention Derived classes must test if m_next equals NULL and if it doesn't
  they have to delete() it.

  On systems where wxWidget supports (and is compiled with)
  accessibility features Cell is derived from wxAccessible which
  allows every element in the worksheet to identify itself to an
  eventual screen reader.

 */
#if wxUSE_ACCESSIBILITY
class Cell: public Observed, public wxAccessible
#else
class Cell: public Observed
#endif
{
  // This class can be derived from wxAccessible which has no copy constructor
  void operator=(const Cell&) = delete;
  Cell(const Cell&) = delete;

public:

  /*! The storage for pointers to cells.
    
    If a cell is deleted it is necessary to remove all pointers that might
    allow to access the now-defunct cell. These pointers are kept in this 
    per-worksheet structure.
  */
  class CellPointers
  {
  public:
    void ScrollToCell(Cell *cell) { m_cellToScrollTo = cell; }
    Cell *CellToScrollTo() { return m_cellToScrollTo; }
    explicit CellPointers(wxScrolledCanvas *worksheet);
    /*! Returns the cell maxima currently works on. NULL if there isn't such a cell.
      
      \param resortToLast true = if we already have set the cell maxima works on to NULL
      use the last cell maxima was known to work on.
    */
    GroupCell *GetWorkingGroup(bool resortToLast = false) const;

    //! Sets the cell maxima currently works on. NULL if there isn't such a cell.
    void SetWorkingGroup(GroupCell *group);
    
    void WXMXResetCounter() { m_wxmxImgCounter = 0; }
    
    wxString WXMXGetNewFileName();
    
    int WXMXImageCount() const { return m_wxmxImgCounter; }

    bool HasCellsSelected() const { return m_selectionStart && m_selectionEnd; }

    //! A list of editor cells containing error messages.
    class ErrorList
    {
    public:
      ErrorList() = default;
      //! Is the list of errors empty?
      bool Empty() const { return m_errors.empty(); }
      //! Remove one specific GroupCell from the list of errors
      void Remove(GroupCell * cell);
      //! Does the list of GroupCell with errors contain cell?
      bool Contains(GroupCell * cell) const;
      //! Mark this GroupCell as containing errors
      void Add(GroupCell * cell);
      //! The first GroupCell with error that is still in the list
      GroupCell *FirstError() const;
      //! The last GroupCell with errors in the list
      GroupCell *LastError() const;
      //! Empty the list of GroupCells with errors
      void Clear() { m_errors.clear(); }
    private:
      //! A list of GroupCells that contain errors
      std::vector<CellPtr<GroupCell>> m_errors;
    };

    //! The list of cells maxima has complained about errors in
    ErrorList m_errorList;
    //! The EditorCell the mouse selection has started in
    CellPtr<EditorCell> m_cellMouseSelectionStartedIn;
    //! The EditorCell the keyboard selection has started in
    CellPtr<EditorCell> m_cellKeyboardSelectionStartedIn;
    //! The EditorCell the search was started in
    CellPtr<EditorCell> m_cellSearchStartedIn;
    //! Which cursor position incremental search has started at?
    int m_indexSearchStartedAt = -1;
    //! Which EditCell the blinking cursor is in?
    CellPtr<EditorCell> m_activeCell;
    //! The GroupCell that is under the mouse pointer
    CellPtr<GroupCell> m_groupCellUnderPointer;
    //! The EditorCell that contains the currently active question from maxima
    CellPtr<EditorCell> m_answerCell;
    //! The last group cell maxima was working on.
    CellPtr<GroupCell> m_lastWorkingGroup;
    //! The textcell the text maxima is sending us was ending in.
    CellPtr<TextCell> m_currentTextCell;
    /*! The group cell maxima is currently working on.

      NULL means that maxima isn't currently evaluating a cell.
    */
    CellPtr<GroupCell> m_workingGroup;
    /*! The currently selected string. 

      Since this string is defined here it is available in every editor cell
      for highlighting other instances of the selected string.
    */
    wxString m_selectionString;

    //! Forget where the search was started
    void ResetSearchStart()
    {
      m_cellSearchStartedIn = {};
      m_indexSearchStartedAt = -1;
    }

    //! Forget where the mouse selection was started
    void ResetMouseSelectionStart()
    { m_cellMouseSelectionStartedIn = {}; }

    //! Forget where the keyboard selection was started
    void ResetKeyboardSelectionStart()
    { m_cellKeyboardSelectionStartedIn = {}; }
  
    /*! The first cell of the currently selected range of Cells.
    
      NULL, when no Cells are selected and NULL, if only stuff inside a EditorCell
      is selected and therefore the selection is handled by EditorCell; This cell is 
      always above m_selectionEnd.
    
      See also m_hCaretPositionStart and m_selectionEnd
    */
    CellPtr<Cell> m_selectionStart;
    /*! The last cell of the currently selected range of groupCells.
    
      NULL, when no GroupCells are selected and NULL, if only stuff inside a GroupCell
      is selected and therefore the selection is handled by EditorCell; This cell is 
      always below m_selectionStart.
    
      See also m_hCaretPositionEnd
    */

    //! The cell currently under the mouse pointer
    CellPtr<Cell> m_cellUnderPointer;
  
    /*! The last cell of the currently selected range of Cells.
    
      NULL, when no Cells are selected and NULL, if only stuff inside a EditorCell
      is selected and therefore the selection is handled by EditorCell; This cell is 
      always above m_selectionEnd.
    
      See also m_hCaretPositionStart, m_hCaretPositionEnd and m_selectionStart.
    */
    CellPtr<Cell> m_selectionEnd;
    std::map<Cell*, int> m_slideShowTimers;

    wxScrolledCanvas *GetWorksheet() { return m_worksheet; }

    //! Is scrolling to a cell scheduled?
    bool m_scrollToCell = false;
  private:
    //! If m_scrollToCell = true: Which cell do we need to scroll to?
    CellPtr<Cell> m_cellToScrollTo;
    //! The object of the function to call if an animation has to be stepped.
    wxScrolledCanvas *const m_worksheet;
    //! The image counter for saving .wxmx files
    int m_wxmxImgCounter = 0;
  };


  Cell(GroupCell *group, Configuration **config);

  /*! Create a copy of this cell

    This method is purely virtual, which means every child class has to define
    its own Copy() method.
   */
  virtual Cell *Copy() const = 0;

  /*! Scale font sizes and line widths according to the zoom factor.

    Is used for displaying/printing/exporting of text/maths
   */
  int Scale_Px(double px) const {return (*m_configuration)->Scale_Px(px);}
  AFontSize Scale_Px(AFontSize size) const { return (*m_configuration)->Scale_Px(size); }

#if wxUSE_ACCESSIBILITY
  // The methods marked final indicate that their implementation within Cell
  // should be sufficient. If that's not the case, the final qualification can be
  // removed with due caution.
  //! Accessibility: Inform the Screen Reader which cell is the parent of this one
  wxAccStatus GetParent (wxAccessible ** parent) override final;
  //! Accessibility: How many childs of this cell GetChild() can retrieve?
  wxAccStatus GetChildCount (int *childCount) override final;
  //! Accessibility: Retrieve a child cell. childId=0 is the current cell
  wxAccStatus GetChild (int childId, wxAccessible **child) override final;
  //! Accessibility: Is pt inside this cell or a child cell?
  wxAccStatus HitTest (const wxPoint &pt,
                      int *childId, wxAccessible **childObject) override final;

  //! Accessibility: Describe the current cell to a Screen Reader
  wxAccStatus GetDescription(int childId, wxString *description) override;
  //! Accessibility: Does this or a child cell currently own the focus?
  wxAccStatus GetFocus (int *childId, wxAccessible **child) override;
  //! Accessibility: Where is this cell to be found?
  wxAccStatus GetLocation (wxRect &rect, int elementId) override;
  //! Accessibility: What is the contents of this cell?
  wxAccStatus GetValue (int childId, wxString *strValue) override;
  wxAccStatus GetRole (int childId, wxAccRole *role) override;
#endif
  

  /*! Returns the ToolTip this cell provides.

    wxEmptyString means: No ToolTip
   */
  virtual wxString GetToolTip(wxPoint point);

  //! Delete this list of cells.
  virtual ~Cell();

  //! How many cells does this cell contain?
  int CellsInListRecursive() const;
  
  //! The part of the rectangle rect that is in the region that is currently drawn
  wxRect CropToUpdateRegion(wxRect rect)
    {
      if(!(*m_configuration)->ClipToDrawRegion())
        return rect;
      else
        return rect.Intersect((*m_configuration)->GetUpdateRegion());
    }

  //! Is part of this rectangle in the region that is currently drawn?
  bool InUpdateRegion(const wxRect &rect);

  //! Is this cell inside the region that is currently drawn?
  bool InUpdateRegion() {return InUpdateRegion(GetRect());}

  /*! Add a cell to the end of the list this cell is part of
    
    \param p_next The cell that will be appended to the list.
   */
  void AppendCell(Cell *p_next);

  //! Do we want this cell to start with a linebreak?
  bool SoftLineBreak(bool breakLine = true)
  {
    bool result = (m_breakLine == breakLine);
    m_breakLine = breakLine;
    return result;
  }

  //! Does this cell to start with a linebreak?
  bool LineBreakAtBeginning() const
  { return m_breakLine || m_breakPage || m_forceBreakLine; }

  //! Do we want this cell to start with a pagebreak?
  void BreakPage(bool breakPage)
  { m_breakPage = breakPage; }

  //! Are we allowed to break a line here?
  bool BreakLineHere() const
    {
      return m_breakLine || m_forceBreakLine;
    }

  //! Does this cell begin with a manual linebreak?
  bool HardLineBreak() const
  { return m_forceBreakLine; }

  //! Does this cell begin with a manual page break?
  bool BreakPageHere() const
  { return m_breakPage; }

  /*! Try to split this command into lines to make it fit on the screen

    \retval true = This cell was split into lines.
  */
  virtual bool BreakUp();

  /*! Is a part of this cell inside a certain rectangle?

    \param sm The rectangle to test for collision with this cell
    \param all
     - true means test this cell and the ones that are following it in the list
     - false means test this cell only.
   */
  bool ContainsRect(const wxRect &sm, bool all = true);

  /*! Is a given point inside this cell?

    \param point The point to test for collision with this cell
   */
  bool ContainsPoint(wxPoint point) { return GetRect().Contains(point); }

  /*! Clears memory from cached items automatically regenerated when the cell is drawn
    
    The scaled version of the image will be recreated automatically once it is 
    needed.
   */
  virtual void ClearCache()
  {}

  /*! Clears the cache of the whole list of cells starting with this one.

    For details see ClearCache().
   */
  void ClearCacheList();

  /*! Draw this cell

    \param point The x and y position this cell is drawn at: All top-level cells get their
    position during recalculation. But for the cells within them the position needs a 
    second step after determining the dimension of the contents of the top-level cell.

    Example: The position of the denominator of a fraction can only be determined
    after the height of denominator and numerator are known.
   */
  virtual void Draw(wxPoint point);

  void Draw(){Draw(m_currentPoint);}

  /*! Draw this list of cells

    \param point The x and y position this cell is drawn at
   */
  void DrawList(wxPoint point);
  void DrawList(){DrawList(m_currentPoint);}

  /*! Draw a rectangle that marks this cell or this list of cells as selected

    \param all
     - true:  Draw the bounding box around this list of cells
     - false: Draw the bounding box around this cell only
     \param dc The drawing context the box is drawn in.
  */
  virtual void DrawBoundingBox(wxDC &WXUNUSED(dc), bool all = false);

  bool DrawThisCell(wxPoint point);
  bool DrawThisCell(){return DrawThisCell(m_currentPoint);}

  /*! Insert (or remove) a forced linebreak at the beginning of this cell.

    \param force
     - true: Insert a forced linebreak
     - false: Remove the forced linebreak
   */
  void ForceBreakLine(bool force = true)
  { m_forceBreakLine = m_breakLine = force; }

  /*! Get the height of this cell

    This value is recalculated by RecalculateHeight; -1 means: Needs to be recalculated.
  */
  int GetHeight() const
  { return m_height; }

  /*! Get the width of this cell

    This value is recalculated by RecalculateWidth; -1 means: Needs to be recalculated.
  */
  int GetWidth() const
  { return m_width; }

  /*! Get the distance between the top and the center of this cell.

    Remember that (for example with double fractions) the center does not have to be in the 
    middle of a cell even if this object is --- by definition --- center-aligned.
   */
  int GetCenter() const
  { return m_center; }

  /*! Get the distance between the center and the bottom of this cell


    Remember that (for example with double fractions) the center does not have to be in the 
    middle of an output cell even if the current object is --- by definition --- 
    center-aligned.

    This value is recalculated by RecalculateHeight; -1 means: Needs to be recalculated.
   */
  int GetDrop() const
  { return m_height - m_center; }

  /*! 
    Returns the type of this cell.
   */
  CellType GetType() const
  { return m_type; }

  /*! Returns the maximum distance between center and bottom of this line

    Note that the center doesn't need to be exactly in the middle of an object.
    For a fraction for example the center is exactly at the middle of the 
    horizontal line.
   */
  int GetMaxDrop();

  /*! Returns the maximum distance between top and center of this line

    Note that the center doesn't need to be exactly in the middle of an object.
    For a fraction for example the center is exactly at the middle of the 
    horizontal line.
  */
  int GetCenterList();

  /*! Returns the total height of this line

    Returns GetCenterList()+GetMaxDrop()
   */
  int GetHeightList();

  //! How many pixels is this list of cells wide, if we don't break it into lines?
  int GetFullWidth();

  /*! How many pixels is the current line of this list of cells wide?

    This command returns the real line width when all line breaks are really performed. 
    See GetFullWidth().
   */
  int GetLineWidth();

  /*! Get the x position of the top left of this cell

    See m_currentPoint for more details.
   */
  int GetCurrentX() const
  { return m_currentPoint.x; }

  /*! Get the y position of the top left of this cell

    See m_currentPoint for more details.
   */
  int GetCurrentY() const
  { return m_currentPoint.y; }

  /*! Get the smallest rectangle this cell fits in

    \param all
      - true: Get the rectangle for this cell and the ones that follow it in the list of cells
      - false: Get the rectangle for this cell only.
   */
  virtual wxRect GetRect(bool all = false);

  //! True, if something that affects the cell size has changed.
  virtual bool NeedsRecalculation(AFontSize fontSize) const;
  
  virtual wxString GetDiffPart() const;

  /*! Recalculate the height of the cell and the difference between top and center

    Must set: m_height, m_center.

    \param fontsize In exponents, super- and subscripts the font size is reduced.
    This cell therefore needs to know which font size it has to be drawn at.
  */
  virtual void RecalculateHeight(AFontSize fontsize);

  /*! Recalculate the height of this list of cells

    \param fontsize In exponents, super- and subscripts the font size is reduced.
    This cell therefore needs to know which font size it has to be drawn at.
   */
  void RecalculateHeightList(AFontSize fontsize);

  /*! Recalculate the width of this cell.

    Must set: m_width.

    \param fontsize In exponents, super- and subscripts the font size is reduced.
    This cell therefore needs to know which font size it has to be drawn at.
   */
  virtual void RecalculateWidths(AFontSize fontsize);

  /*! Recalculates all widths of this list of cells.

    \param fontsize In exponents, super- and subscripts the font size is reduced.
    This cell therefore needs to know which font size it has to be drawn at.
   */
  void RecalculateWidthsList(AFontSize fontsize);

  /*! Recalculate both width and height of this list of cells.

    Is faster than a <code>RecalculateHeightList();RecalculateWidths();</code>.
   */
  void RecalculateList(AFontSize fontsize);

  //! Tell a whole list of cells that their fonts have changed
  void FontsChangedList();

  //! Mark all cached size information as "to be calculated".
  void ResetData();

  //! Mark the cached height information as "to be calculated".
  void ResetSize()
    { 
       m_recalculateWidths = true; 
       m_recalculate_maxCenter = true;
       m_recalculate_maxDrop = true;
       m_recalculate_maxWidth = true;
       m_recalculate_lineWidth = true;
    }

  void ResetCellListSizes()
    { 
      m_recalculate_maxCenter = true;
      m_recalculate_maxDrop = true;
      m_recalculate_maxWidth = true;
      m_recalculate_lineWidth = true;
    }

  //! Mark the cached height information of the whole list of cells as "to be calculated".
  void ResetSizeList();

  void SetSkip(bool skip)
  { m_bigSkip = skip; }

  //! Sets the text style according to the type
  virtual void SetType(CellType type);

  TextStyle GetStyle() const
  { return m_textStyle; }

  // cppcheck-suppress functionStatic
  // cppcheck-suppress functionConst
  void SetPen(double lineWidth = 1.0);

  //! Mark this cell as highlighted (e.G. being in a maxima box)
  void SetHighlight(bool highlight)
  { m_highlight = highlight; }

  //! Is this cell highlighted (e.G. inside a maxima box)
  bool GetHighlight() const
  { return m_highlight; }

  virtual void SetExponentFlag()
  {}

  virtual void SetValue(const wxString &WXUNUSED(text)) {}
  virtual const wxString &GetValue() const;

  //! Get the first cell in this list of cells
  Cell *first() const;

  //! Get the last cell in this list of cells
  Cell *last() const;

  /*! Select a rectangle using the mouse

    \param rect The rectangle to select
    \param first Returns the first cell of the rectangle
    \param last Returns the last cell of the rectangle
   */
  void SelectRect(const wxRect &rect, CellPtr<Cell> *first, CellPtr<Cell> *last);

  /*! The top left of the rectangle the mouse has selected

    \param rect The rectangle the mouse selected
    \param first Returns the first cell of the rectangle
   */
  void SelectFirst(const wxRect &rect, CellPtr<Cell> *first);

  /*! The bottom right of the rectangle the mouse has selected

    \param rect The rectangle the mouse selected
    \param last Returns the last cell of the rectangle
   */
  void SelectLast(const wxRect &rect, CellPtr<Cell> *last);

  /*! Select the cells inside this cell described by the rectangle rect.
  */
  virtual void SelectInner(const wxRect &rect, CellPtr<Cell> *first, CellPtr<Cell> *last);

  //! Is this cell an operator?
  virtual bool IsOperator() const { return false; }

  //! Do we have an operator in this line - draw () in frac...
  bool IsCompound() const;

  virtual bool IsShortNum() const { return false; }

  //! Returns the group cell this cell belongs to
  GroupCell *GetGroup() const;

  //! For the bitmap export we sometimes want to know how big the result will be...
  struct SizeInMillimeters
  {
  public:
    double x, y;
  };

  //! Returns the list's representation as a string.
  virtual wxString ListToString();

  /*! Returns all variable and function names used inside this list of cells.
  
    Used for detecting lookalike chars in function and variable names.
   */
  virtual wxString VariablesAndFunctionsList();

  //! Convert this list to its LaTeX representation
  virtual wxString ListToMatlab();

  //! Convert this list to its LaTeX representation
  virtual wxString ListToTeX();

  //! Convert this list to a representation fit for saving in a .wxmx file
  virtual wxString ListToXML();

  //! Convert this list to a MathML representation
  virtual wxString ListToMathML(bool startofline = false);

  //! Convert this list to an OMML representation
  virtual wxString ListToOMML(bool startofline = false);

  //! Convert this list to an RTF representation
  virtual wxString ListToRTF(bool startofline = false);

  //! Returns the cell's representation as a string.
  virtual wxString ToString();

  /*! Returns the cell's representation as RTF.

    If this method returns wxEmptyString this might mean that this cell is 
    better handled in OMML.
   */
  virtual wxString ToRTF()
  { return wxEmptyString; }

  //! Converts an OMML tag to the corresponding RTF snippet
  wxString OMML2RTF(wxXmlNode *node);

  //! Converts OMML math to RTF math
  wxString OMML2RTF(wxString ommltext);

  /*! Returns the cell's representation as OMML

    If this method returns wxEmptyString this might mean that this cell is 
    better handled in RTF; The OOML can later be translated to the 
    respective RTF maths commands using OMML2RTF.

    Don't know why OMML was implemented in a world that already knows MathML,
    though.
   */
  virtual wxString ToOMML()
  { return wxEmptyString; }

  //! Convert this cell to its Matlab representation
  virtual wxString ToMatlab();

  //! Convert this cell to its LaTeX representation
  virtual wxString ToTeX();

  //! Convert this cell to a representation fit for saving in a .wxmx file
  virtual wxString ToXML();

  //! Convert this cell to a representation fit for saving in a .wxmx file
  virtual wxString ToMathML();

  //! Escape a string for RTF
  static wxString RTFescape(wxString, bool MarkDown = false);

  //! Escape a string for XML
  static wxString XMLescape(wxString);

  // cppcheck-suppress functionStatic
  // cppcheck-suppress functionConst

  /*! Undo breaking this cell into multiple lines

    Some cells have different representations when they contain a line break.
    Examples for this are fractions or a set of parenthesis.

    This function tries to return a cell to the single-line form.
   */
  virtual void Unbreak();

  /*! Unbreak this line

    Some cells have different representations when they contain a line break.
    Examples for this are fractions or a set of parenthesis.

    This function tries to return a list of cells to the single-line form.
  */
  virtual void UnbreakList();

  //! Get the next cell in the list.
  virtual Cell *GetNext() const {return m_next;}
  /*! Get the next cell that needs to be drawn

    In case of potential 2d objects like fractions either the fraction needs to be
    drawn as a single 2D object or the nominator, the cell containing the "/" and 
    the denominator are pointed to by GetNextToDraw() as single separate objects.
   */
  virtual Cell *GetNextToDraw() const = 0;

  /*! Tells this cell which one should be the next cell to be drawn

    If the cell is displayed as 2d object this sets the pointer to the next cell.

    If the cell is broken into lines this sets the pointer of the last of the 
    list of cells this cell is displayed as.
   */
  virtual void SetNextToDraw(Cell *next) = 0;
  template <typename T, typename Del,
            typename std::enable_if<std::is_base_of<Cell, T>::value, bool>::type = true>
  void SetNextToDraw(const std::unique_ptr<T, Del> &ptr) { SetNextToDraw(ptr.get()); }
  template <typename T, typename
                       std::enable_if<std::is_base_of<Cell, T>::value, bool>::type = true>
  void SetNextToDraw(const CellPtr<T> &ptr) { SetNextToDraw(ptr.get()); }

  /*! Determine if this cell contains text that isn't code

    \return true, if this is a text cell, a title cell, a section, a subsection or a sub(n)section cell.
   */
  bool IsComment() const
  {
    return m_type == MC_TYPE_TEXT || m_type == MC_TYPE_SECTION ||
           m_type == MC_TYPE_SUBSECTION || m_type == MC_TYPE_SUBSUBSECTION ||
           m_type == MC_TYPE_HEADING5 || m_type == MC_TYPE_HEADING6 || m_type == MC_TYPE_TITLE;
  }

  //! Return the hide status
  bool IsHidden() const
    { return m_isHidden; }

  virtual void Hide(bool hide = true) { m_isHidden = hide; }

  bool IsEditable(bool input = false) const
  {
    return (m_type == MC_TYPE_INPUT &&
            m_previous && m_previous->m_type == MC_TYPE_MAIN_PROMPT)
           || (!input && IsComment());
  }

  //! Can this cell be popped out interactively in gnuplot?
  virtual bool CanPopOut() const { return false; }
  
  /*! Retrieve the gnuplot source data for this image 

    wxEmptyString means: No such data.
   */
  virtual wxString GnuplotSource() const {return wxEmptyString;}
  /*! Retrieve the gnuplot data file's contents for this image 

    wxEmptyString means: No such data.
   */
  virtual wxString GnuplotData() const{return wxEmptyString;}

  //! Processes a key event.
  virtual void ProcessEvent(wxKeyEvent &WXUNUSED(event))
  {}

  /*! Add a semicolon to a code cell, if needed.

    Defined in GroupCell and EditorCell
  */
  virtual bool AddEnding()
  { return false; }

  virtual void SelectPointText(wxPoint point);
      
  virtual void SelectRectText(wxPoint one, wxPoint two);
  
  virtual void PasteFromClipboard(bool primary = false);
  
  virtual bool CopyToClipboard()
  { return false; }

  virtual bool CutToClipboard()
  { return false; }

  virtual void SelectAll()
  {}

  virtual bool CanCopy() const
  { return false; }

  virtual void SetMatchParens(bool WXUNUSED(match))
  {}

  virtual wxPoint PositionToPoint(AFontSize WXUNUSED(fontsize), int WXUNUSED(pos) = -1)
  { return wxPoint(-1, -1); }

  virtual bool IsDirty() const
  { return false; }

  virtual void SwitchCaretDisplay()
  {}

  virtual void SetFocus(bool WXUNUSED(focus))
  {}

  //! Sets the foreground color
  void SetForeground();

  virtual bool IsActive() const
  { return false; }

  /*! Define which Cell is the GroupCell this list of cells belongs to

    Also automatically sets this cell as the "parent" of all cells of the list.
   */
  void SetGroupList(GroupCell *group);

  //! Define which Sell is the GroupCell this list of cells belongs to
  virtual void SetGroup(GroupCell *group);
  //! Sets the TextStyle of this cell
  virtual void SetStyle(TextStyle style)
  {
    m_textStyle = style;
    ResetData();
  }
  //! Is this cell possibly output of maxima?
  bool IsMath() const;

  bool HasBigSkip() const { return m_bigSkip; }

  int GetImageBorderWidth() const { return m_imageBorderWidth; }

  //! Copy common data (used when copying a cell)
  void CopyCommonData(const Cell & cell);
  //! What to put on the clipboard if this cell is to be copied as text
  void SetAltCopyText(wxString text)
  { m_altCopyText = text; }

  /*! Attach a copy of the list of cells that follows this one to a cell
    
    Used by Cell::Copy().
  */
  Cell *CopyList() const;

  //! Remove this cell's tooltip
  void ClearToolTip() { m_toolTip.Truncate(0); }
  //! Set the tooltip of this math cell. wxEmptyString means: no tooltip.
  void SetToolTip(const wxString &tooltip);
  //! Add another tooltip to this cell
  void AddToolTip(const wxString &tip);
  //! Tells this cell where it is placed on the worksheet
  void SetCurrentPoint(wxPoint point)
  {
    m_currentPoint = point;
    if((m_currentPoint.x >=0) &&
        (m_currentPoint.y >=0))
      m_currentPoint_Last = point;
  }
  //! Tells this cell where it is placed on the worksheet
  void SetCurrentPoint(int x, int y){
    SetCurrentPoint(wxPoint(x,y));
  }
  //! Where is this cell placed on the worksheet?
  wxPoint GetCurrentPoint() const {return m_currentPoint;}
  bool ContainsToolTip() const { return m_containsToolTip; }

  bool IsBrokenIntoLines() const { return m_isBrokenIntoLines; }
  bool GetSuppressMultiplicationDot() const { return m_suppressMultiplicationDot; }
  void SetSuppressMultiplicationDot(bool val) { m_suppressMultiplicationDot = val; }
  void SetHidableMultSign(bool val) { m_isHidableMultSign = val; }

protected:

//** Large objects
//**
  wxString m_toolTip;
  /*! Text that should end up on the clipboard if this cell is copied as text.

     \attention  m_altCopyText is not checked in all cell types!
   */
  wxString m_altCopyText;

//** 8-byte objects
//**
  /*! The point in the work sheet at which this cell begins.

    The begin of a cell is defined as
     - x=the left border of the cell
     - y=the vertical center of the cell. Which (per example in the case of a fraction)
       might not be the physical center but the vertical position of the horizontal line
       between numerator and denominator.

    The current point is recalculated 
     - for GroupCells by GroupCell::RecalculateHeight
     - for EditorCells by it's GroupCell's RecalculateHeight and
     - for Cells when they are drawn.
  */
  wxPoint m_currentPoint{-1, -1};
  wxPoint m_currentPoint_Last{-1, -1};

  //! The zoom factor at the time of the last recalculation.
  double m_lastZoomFactor = -1;

//** 8/4-byte objects
//**

public:
  // TODO WIP on making these fields private (2020-07-07). Do not refactor.
  /*! The next cell in the list of cells

    Reads NULL, if this is the last cell of the list. See also m_nextToDraw and
    m_previous.
   */
  Cell *m_next = nullptr;

  /*! The previous cell in the list of cells

    Reads NULL, if this is the first cell of the list. See also
    m_nextToDraw and m_next
   */
  CellPtr<Cell> m_previous;

protected:
  /*! The GroupCell this list of cells belongs to.
    Reads NULL, if no parent cell has been set - which is treated as an Error by GetGroup():
    every math cell has a GroupCell it belongs to.
  */
  CellPtr<GroupCell> m_group;

  Configuration **m_configuration;
  CellPointers *const m_cellPointers;

//** 4-byte objects
//**

  //! 0 for ordinary cells, 1 for slide shows and diagrams displayed with a 1-pixel border
  int m_imageBorderWidth = 0;

  //! The height of this cell.
  int m_height = -1;
  /*! The width of this cell.

     Is recalculated by RecalculateHeight.
   */
  int m_width = -1;
  /*! Caches the width of the list starting with this cell.

     - Will contain -1, if it has not yet been calculated.
     - Won't be recalculated on appending new cells to the list.
   */
  int m_fullWidth = -1;
  /*! Caches the width of the rest of the line this cell is part of.

     - Will contain -1, if it has not yet been calculated.
     - Won't be recalculated on appending new cells to the list.
   */
  int m_lineWidth = -1;
  int m_center = -1;
  int m_maxCenter = -1;
  int m_maxDrop = -1;
private:
  //! The client width at the time of the last recalculation.
  int m_clientWidth_old = -1;
protected:
  CellType m_type = MC_TYPE_DEFAULT;
  TextStyle m_textStyle = TS_DEFAULT;

//** 2-byte objects
//**
  //! The font size is smaller in super- and subscripts.
  AFontSize m_fontSize = {};
  AFontSize m_fontsize_old = {};

//** 1-byte objects
//**
  bool m_bigSkip = false;

  /*! true means:  This cell is broken into two or more lines.

     Long abs(), conjugate(), fraction and similar cells can be displayed as 2D objects,
     but will be displayed in their linear form (and therefore broken into lines) if they
     end up to be wider than the screen. In this case m_isBrokenIntoLines is true.
   */
  bool m_isBrokenIntoLines = false;
  bool m_isBrokenIntoLines_old = false;

  /*! True means: This cell is not to be drawn.

     Currently the following items fall into this category:
     - parenthesis around fractions or similar things that clearly can be recognized as atoms
     - plus signs within numbers
     - The output in folded GroupCells
   */
  bool m_isHidden = false;

  //! True means: This is a hidable multiplication sign
  bool m_isHidableMultSign = false;

  /*! Do we want to begin this cell with a center dot if it is part of a product?

     Maxima will represent a product like (a*b*c) by a list like the following:
     [*,a,b,c]. This would result us in converting (a*b*c) to the following LaTeX
     code: \\left(\\cdot a ß\\cdot b \\cdot c\\right) which obviously is one \\cdot too
     many => we need parenthesis cells to set this flag for the first cell in
     their "inner cell" list.
   */
  bool m_suppressMultiplicationDot = false;

  //! true, if this cell clearly needs recalculation
  bool m_recalculateWidths = true;
  bool m_recalculate_maxCenter = true;
  bool m_recalculate_maxDrop = true;
  bool m_recalculate_maxWidth = true;
  bool m_recalculate_lineWidth = true;
  //! GroupCells only: Suppress the yellow ToolTips marker
  bool m_suppressTooltipMarker = false;
  bool m_containsToolTip = false;
  //! Does this cell begin with a forced page break?
  bool m_breakPage = false;
  //! Are we allowed to add a line break before this cell?
  bool m_breakLine = false;
  //! true means we force this cell to begin with a line break.
  bool m_forceBreakLine = false;
  bool m_highlight = false;


  class InnerCellIterator
  {
    enum class Uses { SmartPtr, RawPtr};
    using SmartPtr_ = const std::unique_ptr<Cell> *;
    using RawPtr_ = Cell* const*;
    void const* m_ptr = {};
    Uses m_uses = Uses::SmartPtr;
    Cell *GetInner() const
    {
      if (!m_ptr) return {};
      if (m_uses == Uses::SmartPtr) return static_cast<SmartPtr_>(m_ptr)->get();
      else if (m_uses == Uses::RawPtr) return *static_cast<RawPtr_>(m_ptr);
      else return {};
    }
  public:
    InnerCellIterator() = default;
    explicit InnerCellIterator(const std::unique_ptr<Cell> *p) : m_ptr(p), m_uses(Uses::SmartPtr) {}
    explicit InnerCellIterator(Cell* const *p) : m_ptr(p), m_uses(Uses::RawPtr) {}
    InnerCellIterator(const InnerCellIterator &o) = default;
    InnerCellIterator &operator=(const InnerCellIterator &o) = default;
    InnerCellIterator operator++(int)
    {
      auto ret = *this;
      return operator++(), ret;
    }
    InnerCellIterator &operator++()
    {
      if (m_ptr)
      {
        if (m_uses == Uses::SmartPtr) ++reinterpret_cast<SmartPtr_&>(m_ptr);
        else if (m_uses == Uses::RawPtr) ++reinterpret_cast<RawPtr_&>(m_ptr);
        else wxASSERT(false && "Internal error in InnerCellIterator");
      }
      return *this;
    }
    bool operator==(const InnerCellIterator &o) const
    { return m_uses == o.m_uses && m_ptr == o.m_ptr; }
    bool operator!=(const InnerCellIterator &o) const
    { return m_uses != o.m_uses || m_ptr != o.m_ptr; }
    operator bool() const { return GetInner(); }
    operator Cell*() const { return GetInner(); }
    Cell *operator->() const { return GetInner(); }
  };

  //! Iterator to the beginning of the inner cell range
  virtual InnerCellIterator InnerBegin() const;
  //! Iterator to the end of the inner cell range
  virtual InnerCellIterator InnerEnd() const;

  inline Worksheet *GetWorksheet() const;

  //! To be called if the font has changed.
  virtual void FontsChanged()
  {
    ResetSize();
    ResetData();
  }

private:
  void RecalcCenterListAndMaxDropCache();

  CellPointers *GetCellPointers() const;
};

#endif // MATHCELL_H
