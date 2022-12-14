import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jiffy/jiffy.dart';
import 'package:pref/pref.dart';
import 'package:tuple/tuple.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;

import 'local_timetable.dart';
import 'get_new_timetable.dart';
import 'update_link.dart';
import 'settings.dart';
import 'other.dart';

//late final SharedPreferences prefs;
late List<List> timetableData;

const dayNames = [
  "Lunedì",
  "Martedì",
  "Mercoledì",
  "Giovedì",
  "Venerdì",
  "Sabato",
];

// Imposta e carica le cose cose necessarie per il funzionamento dell'app
Future<Tuple2<PrefServiceShared, SharedPreferences>> settingSetup() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Jiffy.locale("it"); // Setta Jiffy in italiano

  // Restituisce il servizio per le impostazioni e un'instanza di SharedPreferences
  return Tuple2<PrefServiceShared, SharedPreferences>(
      await PrefServiceShared.init(
        defaults: {
          'timetableurl': '',
          'listViewPadding': false,
          'hideSubjectSubmenu': false,
        },
      ),
      await SharedPreferences.getInstance());
}

void main() async {
  final setup = await settingSetup();
  timetableData = await prepareTT(setup.item1, setup.item2);
  runApp(
    PrefService(
      service: setup.item1,
      child: const Tableau(),
    ),
  );

  // Probabilmente l'if non è necessario ma lo tengo comunque
  if (!kIsWeb) {
    // Forza il colore della navbar a trasparente
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent, //black.withOpacity(0),
    ));
  }
}

// Prepara la lista dalla tabella oraria
Future<List<List>> prepareTT(
    PrefServiceShared service, SharedPreferences prefs) async {
  final ttD = await readTTFromLocal(prefs);

  // Se restituisce qualsiasi cosa che non sia "nodata"
  if (ttD[0][0] != "nodata") {
    // Check per vedere che la data sia aggiornata
    print(
        "dateinv: ${isDateInvalid(int.parse(ttD[3][2]), int.parse(ttD[3][1]))}");
    print("shul: ${shouldUpdateLink(prefs)}");
    if (isDateInvalid(int.parse(ttD[3][2]), int.parse(ttD[3][1])) &&
        shouldUpdateLink(prefs)) {
      // Se no aggiorna
      String ttUrl = updateLink(ttD[3][3]);
      final ttDNew = await getNewTimetable(ttUrl);
      // Aggiorna lastCheckWeek per evitare continue richieste al server
      if (prefs.getInt('lastCheckWeek') == Jiffy().week) {
        await prefs.setInt(
            'lastCheckWeek',
            Jiffy().week +
                1); // so che quando arriva a 52 continuerebbe a caricare il link dell'orario ma si sa che nessuno guarda l'orario l'ultima settimana dell'anno
      } else {
        await prefs.setInt('lastCheckWeek', Jiffy().week);
      }
      // E se non ritorna "nodata", salvala e restituisci anche ttDNew
      if (ttDNew[0][0] != "nodata") {
        writeTTtoLocal(ttD, prefs);
        return ttDNew;
      } /* else {
        return ttD;
      } */
    }
    // Restituisce la tabella salvata
    return ttD;
  }
  // Se non viene restituito niente, fai come se fosse la prima volta (spesso lo è)
  return [
    ["nodata", "firsttime"],
  ];
}

// Usato per ricaricare la tabella oraria dopo averla impostata nelle impostazioni
void refreshTimetableData(String url) async {
  timetableData = await getNewTimetable(url);
  if (timetableData[0][0] != "nodata") {
    writeTTtoLocal(timetableData, await SharedPreferences.getInstance());
  }
}

void reset() async {
  final prefs = await SharedPreferences.getInstance();
  prefs.clear();
}

class Tableau extends StatelessWidget {
  const Tableau({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    // Carica i colori del tema dinamico
    return DynamicColorBuilder(
        builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
      ColorScheme darkTheme;
      ColorScheme lightTheme;

      // Se non è supportato crea un tema usando bianco e nero
      if (lightDynamic != null && darkDynamic != null) {
        lightTheme = lightDynamic.harmonized();
        darkTheme = darkDynamic.harmonized();
      } else {
        lightTheme = const ColorScheme.light();
        darkTheme = const ColorScheme.dark(
          background: Colors.black,
          surface: Colors.black,
        );
      }

/*       if (UniversalPlatform.isWeb) {
        return const CupertinoApp(
          title: 'Tableau',
          home: TableauMain(title: 'Tableau'),
          localizationsDelegates: <LocalizationsDelegate<dynamic>>[
            DefaultMaterialLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
            DefaultCupertinoLocalizations.delegate,
          ],
        );
      } else { */
      return MaterialApp(
        title: 'Tableau',
        theme: ThemeData(
          colorScheme: lightTheme,
          scaffoldBackgroundColor: lightTheme
              .background, // dynamic_colors non imposta il colore per gli scaffold e quindi lo "forzo" qui
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: darkTheme,
          scaffoldBackgroundColor: darkTheme.background, // e qui
          useMaterial3: true,
        ),
        themeMode: ThemeMode.system,
        home: const TableauMain(title: 'Tableau'),
      );
      //}
    });
  }
}

class TableauMain extends StatefulWidget {
  const TableauMain({super.key, required this.title});

  final String title;

  @override
  State<TableauMain> createState() => _TableauMainState();
}

class _TableauMainState extends State<TableauMain> {
  @override
  Widget build(BuildContext context) {
    // AppBar inizializata qui per evitare di tenere questo blocco di codice per entrambe le situazioni sotto
    AppBar bartender = AppBar(
      title: Text(widget.title),
      actions: [
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: "Impostazioni",
          // Magico blocco di codice che scarica la pagina quando si passa alle impostazioni così almeno funzionano
          // Non capisco bene come funziona però funziona
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => AppSettings()),
            ).then((value) => setState(() {}));
          },
        ),
      ],
    );

    // La lista di liste di liste
    if (timetableData[0][0] != "nodata") {
      final currentDayOfWeek = Jiffy().day -
          1; // Il -1 è necessario dato che Jiffy parte da 1 e le liste da 0
      final hoursADay = timetableData[0].length - 1;
      const listPadding = 16.0;
      return Scaffold(
        appBar: bartender,
        body: ListView(
          // Se physics non è specificato anche quando non serve scrollare la pagina può essere scrollata
          physics: const ScrollPhysics(),
          children: [
            // L'ultima lista creata ovvero la prima che si vede
            ListView.builder(
              //scrollDirection: Axis.vertical,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: dayNames.length,
              itemBuilder: (context, indice) {
                // Espande la lista se il giorno corrispone ad oggi
                return ExpansionTile(
                  tilePadding: PrefService.of(context).get('listViewPadding')
                      ? const EdgeInsets.only(
                          left: listPadding,
                          right: 16,
                        )
                      : null,
                  initiallyExpanded: (indice == currentDayOfWeek),
                  title: Text(dayNames[indice]),
                  children: [
                    // La seconda lista
                    ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        //scrollDirection: Axis.vertical,
                        itemCount: hoursADay,
                        itemBuilder: (BuildContext context, int index) {
                          // Se l'ora è vuota restituisci solo -
                          if (timetableData[0][index + 1][indice] == "-") {
                            return ListTile(
                              title: const Text("-"),
                              // Padding per distinguere meglio la categoria (accessibilità)
                              contentPadding:
                                  PrefService.of(context).get('listViewPadding')
                                      ? const EdgeInsets.only(
                                          left: listPadding * 2,
                                          right: 16,
                                        )
                                      : null,
                            );
                          } else {
                            // Altrimenti la materia (solo materia)
                            if (PrefService.of(context)
                                .get('hideSubjectSubmenu')) {
                              return ListTile(
                                title:
                                    Text(timetableData[0][index + 1][indice]),
                                // Padding per distinguere meglio la categoria (accessibilità)
                                contentPadding: PrefService.of(context)
                                        .get('listViewPadding')
                                    ? const EdgeInsets.only(
                                        left: listPadding * 2,
                                        right: 16,
                                      )
                                    : null,
                              );
                            } else {
                              // Materia + Prof e classe
                              return ExpansionTile(
                                title:
                                    Text(timetableData[0][index + 1][indice]),
                                // Padding per distinguere meglio la categoria (accessibilità)
                                tilePadding: PrefService.of(context)
                                        .get('listViewPadding')
                                    ? const EdgeInsets.only(
                                        left: listPadding * 2,
                                        right: 16,
                                      )
                                    : null,
                                children: [
                                  // Il prof
                                  ListTile(
                                    title: Text(
                                        "Prof: ${timetableData[1][index + 1][indice]}"),
                                    // Padding per distinguere meglio la categoria (accessibilità)
                                    contentPadding: PrefService.of(context)
                                            .get('listViewPadding')
                                        ? const EdgeInsets.only(
                                            left: listPadding * 3,
                                            right: 16,
                                          )
                                        : null,
                                  ),
                                  // E la classe
                                  ListTile(
                                    title: Text(
                                        "Classe: ${timetableData[2][index + 1][indice]}"),
                                    // Padding per distinguere meglio la categoria (accessibilità)
                                    contentPadding: PrefService.of(context)
                                            .get('listViewPadding')
                                        ? const EdgeInsets.only(
                                            left: listPadding * 3,
                                            right: 16,
                                          )
                                        : null,
                                  ),
                                ],
                              );
                            }
                          }
                        })
                  ],
                );
              },
            ),
            // E qui da solo c'è il coordinatore di classe
            // Da sostituire con un'altra lista con il coordinatore e altri dati
            ListTile(
              title: kDebugMode
                  ? Text(
                      "Coord: ${timetableData[3][0]} || Reset completo totale totalissimo 110% not scam")
                  : Text("Coordinatore: ${timetableData[3][0]}"),
              onTap: () {
                if (kDebugMode) reset();
              },
            ),
          ],
        ),
      );
    } else {
      // Se non ci sono dati disponibili metti il messaggio d'errore 'tradotto' e basta
      return Scaffold(
        appBar: bartender,
        body: ListTile(
          title: Text(
            translateError(timetableData[0][1]),
            style: const TextStyle(fontWeight: FontWeight.normal),
          ),
        ),
      );
    }
  }
}
