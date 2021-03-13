# NML Design

NML is a UI library inspired by QML. Everything that is displayed is a sub type
of NElem. When a window is created it is passed one NElem als its root element,
and thats it. Each NElem has a ref to the window that contains it.

Engine run is the main event loop, which first calls `processEvent()` on all
elems until that event is consumed, and then calls draw on all windows which
are flagged to need a redraw.

There are two types of NElemes, prime NElems, which are written in Nim, and use
SDL directly, and composed NElems, which are created using the mkui macro, by
composing other NElems.

The mkui macro will define a new type, and create a constructor for that type,
whichs code is then generated from the DSL within the macro. Proc definitions
in the macro are left as they are, and will be placed before the constructor,
so they can be used within the DSL.

Communication occurs via a signal and slot mechanism similar to qt. However a
signal may only change data, and flag a window for redraw, but it may never
redraw itself, as signals and slots are implemented as callbacks and might be
called in a side thread, while SDL permits drawing only in the main thread.

The recommended application design using NML is MVVM, however, here, we combine
the model and the view model, so lets call it frontend and backend. The
frontend (i.e. a composed NElem, that is the rootElem of a window) will take a 
ref to an existing backend instance

There are multiple different communications that can occur:
- *The backend wants to inform the frontend*. In this case, the frontend can
  define slots, which trigger in reaction to the backends signals.
- *The front end wants to talk to the backend*. In this case, since the
  frontend holds a ref to the backend, it can simply call what ever method is
  appropriate 
- *two Frontend components want to talk to each other*. In this case its the
  parent components job to define a slot for the informing components signal, and
  then call the listening components methods appropriatly

For things like lists, there is a model and a delegate. The delegate takes a
function, that returns the actual delegate (i.e. a delegate factory). The
factory will be passed an instance of type T which is what ever is in the
model. For the delegate to be able to inform the backend do something like
this:

```nim
m(ui1, contr: MailControler):
  HLayout:
    MailList:
      model cont.mails
      delegate (containerElem) => newDelegate(contr, containerElem)
```

The model is then supposed to inherit from a yet to be specified class, which
will automatically handle changes in the data
