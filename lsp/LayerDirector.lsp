;;----------------------------------------------------------------------;;
;;  LayerDirector 2026 - LDM Priority                                  ;;
;;----------------------------------------------------------------------;;

(vl-load-com)

;; Initialize global variables
(if (not ldm:current_prefix) (setq ldm:current_prefix "LA-"))
(if (not ldm:old_layer) (setq ldm:old_layer (getvar "CLAYER")))

;;----------------------------------------------------------------------;;
;;  Layer validation and creation                                       ;;
;;----------------------------------------------------------------------;;
(defun ldm:make_layer ( lay_name col /  )
  (if (and lay_name (/= lay_name ""))
    (if (not (tblsearch "layer" lay_name))
      (entmake 
        (list 
          '(0 . "LAYER") 
          '(100 . "AcDbSymbolTableRecord") 
          '(100 . "AcDbLayerTableRecord") 
           (cons 2 lay_name) 
           (cons 62 (if col col 7)) 
          '(6 . "Continuous") 
          '(70 . 0)
        )
      )
    )
  )
)


;;----------------------------------------------------------------------;;
;;  Safe system-variable helpers                                        ;;
;;----------------------------------------------------------------------;;
(defun ldm:getvar_safe ( var_name / result )
  (setq result (vl-catch-all-apply 'getvar (list var_name)))
  (if (vl-catch-all-error-p result)
    nil
    result
  )
)

(defun ldm:setvar_safe ( var_name value / result )
  (setq result (vl-catch-all-apply 'setvar (list var_name value)))
  (not (vl-catch-all-error-p result))
)

(defun ldm:override_annotation_var ( var_name layer_name / old_value )
  ;; Some older AutoCAD versions do not provide every annotation-layer
  ;; system variable. Unsupported variables are ignored safely.
  (setq old_value (ldm:getvar_safe var_name))
  (if old_value
    (progn
      (setq ldm:old_annotation_vars
        (cons (cons var_name old_value) ldm:old_annotation_vars)
      )
      (ldm:setvar_safe var_name layer_name)
    )
  )
)

(defun ldm:restore_annotation_vars ( / item )
  (foreach item ldm:old_annotation_vars
    (ldm:setvar_safe (car item) (cdr item))
  )
  (setq ldm:old_annotation_vars nil)
)

;;----------------------------------------------------------------------;;
;;  Reactor callback 1: command start                                   ;;
;;----------------------------------------------------------------------;;
(defun ldm:start_callback ( obj arg / cmd layer_name )
  (setq cmd (car arg))
  (if (and cmd (= 'str (type cmd)) ldm:current_prefix (= 'str (type ldm:current_prefix)))
    (progn
      (setq cmd (strcase cmd))
      (setq layer_name nil)
      
      ;; Detect the current command
      (cond
        ((or (wcmatch cmd "*TEXT") (wcmatch cmd "*LEADER"))
         (setq layer_name (strcat ldm:current_prefix "text"))
        )
        ((or (wcmatch cmd "DIM*") (= cmd "QPDIM"))
         (setq layer_name (strcat ldm:current_prefix "dim"))
        )
      )
      
      ;; Process text, leader, and dimension commands
      (if (and layer_name (/= layer_name ""))
        (progn
          ;; 1. Save the original layer and entity defaults
          (setq ldm:old_layer (getvar "CLAYER"))
          (setq ldm:old_vars
            (list
              (getvar "CECOLOR")
              (getvar "CELTYPE")
              (getvar "CELWEIGHT")
              (getvar "CETRANSPARENCY")
            )
          )
          (setq ldm:old_annotation_vars nil)

          ;; 2. Create the LDM-managed layer before assigning it anywhere
          (ldm:make_layer layer_name 1) ;; Default color: red

          ;; 3. Temporarily override AutoCAD annotation-layer settings.
          ;;    This prevents DIMLAYER, TEXTLAYER, or MLEADERLAYER from
          ;;    overriding the layer selected by LayerDirector.
          (cond
            ((wcmatch cmd "*TEXT")
             (ldm:override_annotation_var "TEXTLAYER" layer_name)
            )
            ((wcmatch cmd "*LEADER")
             (ldm:override_annotation_var "MLEADERLAYER" layer_name)
            )
            ((or (wcmatch cmd "DIM*") (= cmd "QPDIM"))
             (ldm:override_annotation_var "DIMLAYER" layer_name)
            )
          )

          ;; 4. Force entity defaults back to ByLayer
          (setvar "CECOLOR" "bylayer")
          (setvar "CELTYPE" "bylayer")
          (setvar "CELWEIGHT" -1)
          (setvar "CETRANSPARENCY" -1)

          ;; 5. LDM has final priority while the managed command is active
          (setvar "CLAYER" layer_name)
        )
      )
      
      ;; Store the last entity before attaching an XRef
      (if (wcmatch cmd "XATTACH,CLASSICXREF")
        (setq ldm:entlast (entlast))
      )
    )
  )
  (princ)
)

;;----------------------------------------------------------------------;;
;;  Reactor callback 2: command end, cancel, or failure                 ;;
;;----------------------------------------------------------------------;;
(defun ldm:end_callback ( obj arg / cmd ent enx xrf xlay )
  (setq cmd (car arg))
  (if (and cmd (= 'str (type cmd)))
    (progn
      (setq cmd (strcase cmd))
      
      ;; 1. Restore the original layer and entity defaults
      (if (or (wcmatch cmd "*TEXT")
              (wcmatch cmd "*LEADER")
              (wcmatch cmd "DIM*")
              (= cmd "QPDIM"))
        (progn
          ;; Restore user annotation-layer preferences first. They remain
          ;; unchanged outside the short period controlled by LayerDirector.
          (ldm:restore_annotation_vars)

          (if (and ldm:old_layer (tblsearch "layer" ldm:old_layer))
            (setvar "CLAYER" ldm:old_layer)
          )
          (if ldm:old_vars
            (progn
              (setvar "CECOLOR" (nth 0 ldm:old_vars))
              (setvar "CELTYPE" (nth 1 ldm:old_vars))
              (setvar "CELWEIGHT" (nth 2 ldm:old_vars))
              (setvar "CETRANSPARENCY" (nth 3 ldm:old_vars))
            )
          )
        )
      )
      
      ;; Move newly attached XRefs to an XREF-prefixed layer
      (if (wcmatch cmd "XATTACH,CLASSICXREF")
        (progn
          (if (= 'ename (type ldm:entlast))
            (setq ent (entnext ldm:entlast))
            (setq ent (entnext))
          )
          (while ent
            (setq enx (entget ent))
            (if (and (= "INSERT" (cdr (assoc 0 enx)))
                     (setq xrf (cdr (assoc 2 enx)))
                     (= 4 (logand 4 (cdr (assoc 70 (tblsearch "block" xrf)))))
                )
              (progn
                (setq xlay (strcat "XREF-" xrf))
                (ldm:make_layer xlay 250)
                (vlax-put-property (vlax-ename->vla-object ent) 'Layer xlay)
              )
            )
            (setq ent (entnext ent))
          )
          (setq ldm:entlast nil)
        )
      )
    )
  )
  (princ)
)

;;----------------------------------------------------------------------;;
;;  Reactor core controls with silent mode                              ;;
;;----------------------------------------------------------------------;;
(defun ldm:on_core ( silent )
  (ldm:off_core t)
  (if (or (not ldm:current_prefix) (/= 'str (type ldm:current_prefix)))
    (setq ldm:current_prefix "LA-")
  )
  (setq ldm:reactor 
    (vlr-command-reactor "LDM_REACTOR" 
      '(
        (:vlr-commandwillstart . ldm:start_callback)
        (:vlr-commandended     . ldm:end_callback)
        (:vlr-commandcancelled . ldm:end_callback)
        (:vlr-commandfailed    . ldm:end_callback)
       )
    )
  )
  (if (not silent)
    (princ (strcat "\n[LayerDirector] Enabled. Current prefix: [" ldm:current_prefix "]"))
  )
  (princ)
)

(defun ldm:off_core ( silent )
  (if ldm:reactor
    (progn (vlr-remove ldm:reactor) (setq ldm:reactor nil))
  )
  (foreach grp (vlr-reactors :vlr-command-reactor)
    (foreach obj (cdr grp)
      (if (= "LDM_REACTOR" (vlr-data obj)) (vlr-remove obj))
    )
  )
  (if (not silent)
    (princ "\n[LayerDirector] Disabled.")
  )
  (princ)
)

;; Public commands: LDON and LDOFF display status messages
(defun c:ldon () (ldm:on_core nil))
(defun c:ldoff () (ldm:off_core nil))

;;----------------------------------------------------------------------;;
;;  DCL control panel                                                   ;;
;;----------------------------------------------------------------------;;
(defun c:LDM ( / dcl_id act selected_prefix radio_key )
  (ldm:off_core t) ;; Disable silently while the dialog is open
  (vl-catch-all-apply
    '(lambda ()
       (setq dcl_id (load_dialog_inline_clean))
       (if (new_dialog "laydir_clean" dcl_id)
         (progn
           (set_tile "title" "LayerDirector")
           (setq radio_key
             (cond
               ((= ldm:current_prefix "A-")  "rad_a")
               ((= ldm:current_prefix "LA-") "rad_la")
               ((= ldm:current_prefix "FC-") "rad_fc")
               ((= ldm:current_prefix "RC-") "rad_rc")
               ((= ldm:current_prefix "SO-") "rad_so")
               ((= ldm:current_prefix "EM-") "rad_em")
               ((= ldm:current_prefix "E-")  "rad_e")
               ((= ldm:current_prefix "D-")  "rad_d")
               (t "rad_la")
             )
           )
           (set_tile radio_key "1")
           (setq selected_prefix ldm:current_prefix)
           
           (action_tile "rad_a"  "(setq selected_prefix \"A-\")")
           (action_tile "rad_la" "(setq selected_prefix \"LA-\")")
           (action_tile "rad_fc" "(setq selected_prefix \"FC-\")")
           (action_tile "rad_rc" "(setq selected_prefix \"RC-\")")
           (action_tile "rad_so" "(setq selected_prefix \"SO-\")")
           (action_tile "rad_em" "(setq selected_prefix \"EM-\")")
           (action_tile "rad_e"  "(setq selected_prefix \"E-\")")
           (action_tile "rad_d"  "(setq selected_prefix \"D-\")")
           
           (action_tile "accept" "(done_dialog 1)")
           (action_tile "cancel" "(done_dialog 0)")
           
           (setq act (start_dialog))
           (unload_dialog dcl_id)
           
           (if (= act 1)
             (progn
               (setq ldm:current_prefix selected_prefix)
               (ldm:on_core t) ;; Re-enable silently
               (princ (strcat "\n[LayerDirector] Prefix changed to [" ldm:current_prefix "]."))
             )
             (ldm:on_core t) ;; Re-enable silently
           )
         )
         (ldm:on_core t) ;; Re-enable silently
       )
     )
  )
  (princ)
)

(defun load_dialog_inline_clean ( / f dcl_name dcl_id )
  (setq dcl_name (vl-filename-mktemp "ldm_c" nil ".dcl")
        f (open dcl_name "w")
  )
  (write-line "laydir_clean : dialog {" f)
  (write-line "    key = \"title\"; label = \"\";" f)
  (write-line "    : boxed_radio_column { label = \"Select drawing type\"; key = \"rad_theme\";" f)
  (write-line "        : radio_button { key = \"rad_la\"; label = \"LA-  Furniture / Plan\"; }" f)
  (write-line "        : radio_button { key = \"rad_rc\"; label = \"RC-  Reflected Ceiling\"; }" f)
  (write-line "        : radio_button { key = \"rad_fc\"; label = \"FC-  Floor Finish\"; }" f)
  (write-line "        : radio_button { key = \"rad_so\"; label = \"SO-  Setting Out\"; }" f)
  (write-line "        : radio_button { key = \"rad_em\"; label = \"EM-  Electrical / Mechanical\"; }" f)
  (write-line "        : radio_button { key = \"rad_e\";  label = \"E-   Elevation\"; }" f)
  (write-line "        : radio_button { key = \"rad_d\";  label = \"D-   Detail\"; }" f)
  (write-line "        : radio_button { key = \"rad_a\";  label = \"A-   Architecture\"; }" f)
  (write-line "    }" f)
  (write-line "    : spacer { height = 1; }" f)
  (write-line "    ok_cancel;" f)
  (write-line "}" f)
  (close f)
  (setq dcl_id (load_dialog dcl_name))
  (vl-file-delete dcl_name)
  dcl_id
)

;; Initialize the command reactor on load without duplicate messages.
(ldm:on_core t)
(princ (strcat "\n[LayerDirector] Loaded. Current prefix: [" ldm:current_prefix "]. Type LDM to switch."))
(princ)
