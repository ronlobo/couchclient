//Copyright (C) 2013 Potix Corporation. All Rights Reserved.
//History: Thu, Mar 07, 2013  02:19:30 PM
// Author: hernichen

part of couchclient;

/**
 * The ViewDesign object represents a view to be stored and retrieved
 * from the Couchbase cluster.
 */
class ViewDesign {
  /**
   * The name of the view.
   */
  final String name;

  /**
   * The map function of the view.
   */
  final String map;

  /**
   * The optional reduce function of the view.
   */
  final String reduce;

  /**
   * Create a ViewDesign with a name, map and reduce function.
   *
   * @param name the name of the view.
   * @param map the map function of the view.
   * @param reduce the reduce function of the view.
   */
  ViewDesign(this.name, this.map, [String reduce = null])
      : this.reduce = reduce == null ? '' : reduce;
}